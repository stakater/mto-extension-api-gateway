// Schema validator for the custom resources the charts render (Gateway API,
// cert-manager, and later Connectivity Link and Istio kinds).
//
// Taken from mto-extension-vault-enterprise, where it validates
// vault-config-operator CRs, and generalised: it owns every API group that has a
// CRD in <crd-dir> (hack/crds). An object of an owned group must have a CRD for
// its kind and version; objects of other groups (ConfigMaps, …) are skipped.
//
// Nothing else in this repo reads those schemas, so a field renamed on either
// side still renders and still passes every yq assertion. Template Operator
// writes with server-side apply, which rejects an undeclared field outright, so
// the TemplateInstance fails and the object is never created — and a failed
// TemplateInstance is not something anything alerts on.
//
// So this runs the apiserver's own admission pipeline against the CRDs: prune,
// default, then validate metadata, OpenAPI and CEL. The pruning diff finds
// exactly the fields SSA would reject.
//
// Usage: go run ./hack/crd-validate [-allow-empty] [-min N] <crd-dir> <file|->
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	apiextensions "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions"
	apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	structuralschema "k8s.io/apiextensions-apiserver/pkg/apiserver/schema"
	schemacel "k8s.io/apiextensions-apiserver/pkg/apiserver/schema/cel"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/schema/defaulting"
	schemaobjectmeta "k8s.io/apiextensions-apiserver/pkg/apiserver/schema/objectmeta"
	"k8s.io/apiextensions-apiserver/pkg/apiserver/schema/pruning"
	apiservervalidation "k8s.io/apiextensions-apiserver/pkg/apiserver/validation"
	apivalidation "k8s.io/apimachinery/pkg/api/validation"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	utiljson "k8s.io/apimachinery/pkg/util/json"
	"k8s.io/apimachinery/pkg/util/validation/field"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	celconfig "k8s.io/apiserver/pkg/apis/cel"
	"sigs.k8s.io/yaml"
)

// group labels the checked objects in messages; loadCRDs returns the owned groups.
const group = "vendored-CRD"

type crdEntry struct {
	structural *structuralschema.Structural
	props      *apiextensions.JSONSchemaProps
	cel        *schemacel.Validator
}

func main() {
	// A component slice can legitimately render nothing; a full render cannot.
	allowEmpty := flag.Bool("allow-empty", false, "do not fail when the input contains no objects of a vendored CRD's group")
	// "OK 1" and "OK 42" read alike, so a collapsed render still looks like a pass.
	minObjects := flag.Int("min", 0, "fail if fewer than N objects of vendored CRD groups were checked")
	flag.Parse()
	if flag.NArg() != 2 {
		fmt.Println("usage: crd-validate [-allow-empty] <crd-dir> <rendered.yaml|->")
		os.Exit(2)
	}
	crds, owned, err := loadCRDs(flag.Arg(0))
	if err != nil {
		fmt.Println("CRD-LOAD-ERROR", err)
		os.Exit(2)
	}
	if len(crds) == 0 {
		fmt.Println("CRD-LOAD-ERROR no CRDs found in", flag.Arg(0))
		os.Exit(2)
	}

	docs, err := readDocs(flag.Arg(1))
	if err != nil {
		fmt.Println("READ-ERROR", err)
		os.Exit(2)
	}

	var problems []string
	checked := 0
	for i, doc := range docs {
		if strings.TrimSpace(string(doc)) == "" {
			continue
		}
		// Decode like the apiserver: YAML to JSON, then apimachinery's JSON
		// decoder, which keeps whole numbers as int64. A plain unmarshal gives
		// float64, and CEL rules that compare integers (Gateway's listener
		// uniqueness rule) then fail on a type error the apiserver never sees.
		obj := map[string]interface{}{}
		raw, err := yaml.YAMLToJSON(doc)
		if err == nil {
			err = utiljson.Unmarshal(raw, &obj)
		}
		if err != nil {
			// Never skip silently: helm cannot emit invalid YAML today, so
			// reaching this means something upstream changed.
			problems = append(problems, fmt.Sprintf("document %d: undecodable: %v", i+1, err))
			continue
		}
		u := unstructured.Unstructured{Object: obj}
		gvk := u.GroupVersionKind()
		if !owned[gvk.Group] {
			continue
		}
		key := gvk.Kind + "/" + gvk.Version
		entry, ok := crds[key]
		if !ok {
			problems = append(problems, fmt.Sprintf(
				"%s %s: no vendored CRD for %s — add it to hack/crds",
				gvk.Kind, u.GetName(), key))
			continue
		}
		checked++
		// An over-long name is itself a failure reported here; echoing all 253
		// characters per line buries it.
		name := u.GetName()
		if len(name) > 40 {
			name = name[:40] + "…"
		}
		id := fmt.Sprintf("%s %s", gvk.Kind, name)

		// Mirror the apiserver's order: prune, then default, then validate.
		// Defaulting matters — a field can be both `required` and carry a
		// `default`, which validates only because defaulting ran first.
		admitted := runtime.DeepCopyJSON(obj)
		pruning.Prune(admitted, entry.structural, true)
		if dropped := droppedPaths(obj, admitted); len(dropped) > 0 {
			problems = append(problems, fmt.Sprintf(
				"%s: not declared in the CRD schema: %s", id, strings.Join(dropped, ", ")))
		}
		defaulting.Default(admitted, entry.structural)

		// The apiserver's strategy runs three checks, not one; dropping any makes
		// "validates like the apiserver" false until a real apply is rejected.
		//
		// 1. metadata — names, labels, annotations, which OpenAPI never sees.
		//    Two calls because the apiserver uses two: the accessor for the
		//    resource's own metadata, schemaobjectmeta for embedded resources.
		//    Pruning keeps the root metadata as it is, so a misspelt key there
		//    (metadata.annotaions) passes both calls; the apiserver drops it
		//    or refuses it, depending on field validation, and never applies it
		//    as meant. A strict decode into ObjectMeta names it.
		if err := strictObjectMeta(obj["metadata"]); err != nil {
			problems = append(problems, fmt.Sprintf("%s: metadata: %v", id, err))
		}
		metaObj := &unstructured.Unstructured{Object: admitted}
		for _, e := range apivalidation.ValidateObjectMetaAccessor(
			metaObj, true, apivalidation.NameIsDNSSubdomain, field.NewPath("metadata")) {
			problems = append(problems, fmt.Sprintf("%s: %s", id, e.Error()))
		}
		for _, e := range schemaobjectmeta.Validate(nil, admitted, entry.structural, true) {
			problems = append(problems, fmt.Sprintf("%s: %s", id, e.Error()))
		}
		// 2. OpenAPI — types, required, enums, patterns, formats.
		validator, _, err := apiservervalidation.NewSchemaValidator(entry.props)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: building validator: %v", id, err))
			continue
		}
		if err := apiservervalidation.ValidateCustomResource(nil, admitted, validator); err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", id, err))
		}
		// 3. CEL — the cross-field invariants a schema cannot express, e.g.
		//    "exactly one of spec.kvV2, spec.transit, spec.pki must be set".
		celErrs, _ := entry.cel.Validate(context.TODO(), nil, entry.structural,
			admitted, nil, celconfig.RuntimeCELCostBudget)
		for _, e := range celErrs {
			problems = append(problems, fmt.Sprintf("%s: %s", id, e.Error()))
		}
	}

	// Problems first: an undecodable document checks zero objects, so reporting
	// "no objects" ahead of it would hide the cause.
	if len(problems) > 0 {
		fmt.Printf("FAIL %d problem(s) across %d %s objects\n", len(problems), checked, group)
		for _, p := range problems {
			fmt.Println(" -", p)
		}
		os.Exit(1)
	}
	if checked == 0 && !*allowEmpty {
		fmt.Println("NO-OBJECTS no", group, "resources in", flag.Arg(1))
		os.Exit(2)
	}
	if checked < *minObjects {
		fmt.Printf("TOO-FEW checked %d %s objects, expected at least %d\n", checked, group, *minObjects)
		os.Exit(1)
	}
	fmt.Printf("OK %d objects validate against the vendored CRDs\n", checked)
}

// strictObjectMeta decodes a metadata map into ObjectMeta and fails on a key
// ObjectMeta does not have.
func strictObjectMeta(m any) error {
	raw, err := json.Marshal(m)
	if err != nil {
		return err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	var om metav1.ObjectMeta
	return dec.Decode(&om)
}

// readDocs splits a manifest using apimachinery's reader — the same splitter
// kubectl uses. It is line-based, so a bare --- at column 0 inside a block
// scalar still fragments the document; that matches what a real apply would do.
// Helm indents block scalar content, so the charts cannot produce that shape.
func readDocs(path string) ([][]byte, error) {
	var r io.Reader = os.Stdin
	if path != "-" {
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		defer f.Close()
		r = f
	}
	reader := utilyaml.NewYAMLReader(bufio.NewReader(r))
	var docs [][]byte
	for {
		doc, err := reader.Read()
		if err == io.EOF {
			return docs, nil
		}
		if err != nil {
			return nil, err
		}
		docs = append(docs, doc)
	}
}

// droppedPaths reports the dotted paths pruning removed, which are exactly the
// fields the apiserver would accept and then discard.
func droppedPaths(before, after map[string]interface{}) []string {
	var dropped []string
	diffPaths("", before, after, &dropped)
	sort.Strings(dropped)
	return dropped
}

func diffPaths(prefix string, before, after map[string]interface{}, out *[]string) {
	for k, bv := range before {
		path := k
		if prefix != "" {
			path = prefix + "." + k
		}
		av, present := after[k]
		if !present {
			*out = append(*out, path)
			continue
		}
		bm, bok := bv.(map[string]interface{})
		am, aok := av.(map[string]interface{})
		if bok && aok {
			diffPaths(path, bm, am, out)
			continue
		}
		bl, bok := bv.([]interface{})
		al, aok := av.([]interface{})
		if bok && aok && len(bl) == len(al) {
			for i := range bl {
				bem, bok := bl[i].(map[string]interface{})
				aem, aok := al[i].(map[string]interface{})
				if bok && aok {
					diffPaths(fmt.Sprintf("%s[%d]", path, i), bem, aem, out)
				}
			}
			continue
		}
		if !reflect.DeepEqual(bv, av) {
			*out = append(*out, path)
		}
	}
}

// loadCRDs indexes every served version of every CRD in dir by "Kind/version",
// and returns the set of API groups those CRDs own.
func loadCRDs(dir string) (map[string]crdEntry, map[string]bool, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, nil, err
	}
	out := map[string]crdEntry{}
	owned := map[string]bool{}
	for _, f := range files {
		raw, err := os.ReadFile(f)
		if err != nil {
			return nil, nil, err
		}
		var ext apiextv1.CustomResourceDefinition
		if err := yaml.Unmarshal(raw, &ext); err != nil {
			return nil, nil, fmt.Errorf("%s: %w", filepath.Base(f), err)
		}
		owned[ext.Spec.Group] = true
		var internal apiextensions.CustomResourceDefinition
		if err := apiextv1.Convert_v1_CustomResourceDefinition_To_apiextensions_CustomResourceDefinition(&ext, &internal, nil); err != nil {
			return nil, nil, fmt.Errorf("%s: %w", filepath.Base(f), err)
		}
		for i := range internal.Spec.Versions {
			v := internal.Spec.Versions[i]
			if !v.Served {
				continue
			}
			// The v1→internal conversion hoists a schema shared by every
			// version to spec.validation and clears the per-version one, so a
			// single-version CRD lands there rather than on the version.
			val := v.Schema
			if val == nil {
				val = internal.Spec.Validation
			}
			if val == nil || val.OpenAPIV3Schema == nil {
				continue
			}
			s, err := structuralschema.NewStructural(val.OpenAPIV3Schema)
			if err != nil {
				return nil, nil, fmt.Errorf("%s %s: %w", filepath.Base(f), v.Name, err)
			}
			out[internal.Spec.Names.Kind+"/"+v.Name] = crdEntry{
				structural: s,
				props:      val.OpenAPIV3Schema,
				cel:        schemacel.NewValidator(s, true, celconfig.PerCallLimit),
			}
		}
	}
	return out, owned, nil
}
