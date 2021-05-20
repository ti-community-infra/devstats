package devstatscode

import (
	"regexp"
	"testing"
)

func TestAnnotationRegexp(t *testing.T) {
	// Test cases
	var testCases = []struct {
		re    string
		str   string
		match bool
	}{
		{re: `^(v\d+\.\d+\.\d+|release-\d{4}-\d{2}-\d{2})$`, str: "v1.2.3", match: true},
		{re: `^(v\d+\.\d+\.\d+|release-\d{4}-\d{2}-\d{2})$`, str: "v1.2", match: false},
		{re: `^(v\d+\.\d+\.\d+|release-\d{4}-\d{2}-\d{2})$`, str: "v1.2.3.4", match: false},
		{re: `^(v\d+\.\d+\.\d+|release-\d{4}-\d{2}-\d{2})$`, str: "release-2021-05-15", match: true},
		{re: `^(v\d+\.\d+\.\d+|release-\d{4}-\d{2}-\d{2})$`, str: "release-201-05-15", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v0.0", match: true},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v1.0", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "0.0", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: " v0.0 ", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v1.0.0", match: true},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v1.15.0", match: true},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v0.0.0", match: true},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "v1.2.3", match: false},
		{re: `^v((0\.\d+)|(\d+\.\d+\.0))$`, str: "V1.4.9", match: false},
		{re: `^v?\d+\.\d+\.0$`, str: "v0.0.0", match: true},
		{re: `^v?\d+\.\d+\.0$`, str: "v1.0.0", match: true},
		{re: `^v?\d+\.\d+\.0$`, str: "0.12.0", match: true},
		{re: `^v(\d+\.){1,2}\d+$`, str: "v1.1", match: true},
		{re: `^v(\d+\.){1,2}\d+$`, str: "v2.3.4", match: true},
		{re: `^v(\d+\.){1,2}\d+$`, str: "v1.2.3.4", match: false},
		{re: `^(release-\d+\.\d+\.\d+|\d+\.\d+\.0)$`, str: "release-0.1.2", match: true},
		{re: `^(release-\d+\.\d+\.\d+|\d+\.\d+\.0)$`, str: "1.2.0", match: true},
		{re: `^(release-\d+\.\d+\.\d+|\d+\.\d+\.0)$`, str: "release-0.1", match: false},
		{re: `^(release-\d+\.\d+\.\d+|\d+\.\d+\.0)$`, str: "2.3.4", match: false},
		{re: `^jenkins-\d+\.\d+$`, str: "2.3.4", match: false},
		{re: `^jenkins-\d+\.\d+$`, str: "jenkins-2", match: false},
		{re: `^jenkins-\d+\.\d+$`, str: "jenkins-2.1", match: true},
		{re: `^jenkins-\d+\.\d+$`, str: "jenkins-2.1.1", match: false},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "1.2.3", match: false},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "v0.1.2", match: true},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "v000", match: true},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "007", match: false},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "v007", match: true},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "v0000", match: false},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "05", match: false},
		{re: `^v(\d+\.\d+\.\d+|\d\d\d)$`, str: "v0.2", match: false},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "1.2.3", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.12.23", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-", match: false},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-a", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-.", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1--", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-+", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-0", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "1.0.1-rc.1", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-alpha", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "1.0.1-beta2", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-rc.3", match: true},
		{re: `^v?\d+\.\d+\.\d+(-[\w-+\d.]+)?$`, str: "v1.0.1-al b", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.0", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.10", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.05", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.5", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.50", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.49", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.51", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.55", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.11", match: false},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.0.100", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v1.3.150", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v3.0.200", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v0.5.500", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v10.10.550", match: true},
		{re: `^v\d+\.\d+\.(0|\d*[05]0)$`, str: "v10.10.520", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "vendor/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_vendor/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/vendor/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/vendor/a", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "vendor//", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_vendor/abc/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/vendor/ abc", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "vendor", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "vendor_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/vendor", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/vendor", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/vendor_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/vendor_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "Godeps/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_Godeps/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/Godeps/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/Godeps/a", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "Godeps//", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_Godeps/abc/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/Godeps/ abc", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "Godeps", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "Godeps_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/Godeps", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/Godeps", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/Godeps_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/Godeps_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "workspace/", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_workspace/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "__workspace/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/workspace/", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/_workspace/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/__workspace/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/workspace/a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/_workspace/a", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/__workspace/a", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "workspace//", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_workspace/abc/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "__workspace/abc/", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/workspace/ abc", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/_workspace/ abc", match: true},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "workspace_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "_workspace_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/_workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/_workspace", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/workspace_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "/_workspace_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/workspace_a", match: false},
		{re: `(^|/)_?(vendor|Godeps|_workspace)/`, str: "abc/_workspace_a", match: false},
		{re: `(?i)^(plexistor|stack\s*point\s*cloud|greenqloud|netapp)(,?\s*inc\.?)?$`, str: "GreenQLoud, Inc.", match: true},
		{re: `^\d+\.(0|\d+0)$`, str: "0.0", match: true},
		{re: `^\d+\.(0|\d+0)$`, str: "0.10", match: true},
		{re: `^\d+\.(0|\d+0)$`, str: "1.220", match: true},
		{re: `^\d+\.(0|\d+0)$`, str: "2.00", match: true},
		{re: `^\d+\.(0|\d+0)$`, str: "2.11", match: false},
		{re: `^\d+\.(0|\d+0)$`, str: "0.73", match: false},
		{re: `^\d+\.(0|\d+0)$`, str: "0.a0", match: false},
		{re: `^\d+\.(0|\d+0)$`, str: "2.10.0", match: false},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v0.0.0", match: true},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v0.0.1", match: false},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v0.0.10", match: true},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v0.0.12", match: false},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v1.16.10+k3s1", match: true},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v1.16.10-k3s1", match: false},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v1.16.11+k3s1", match: false},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v1.12.0+k3s.1", match: true},
		{re: `^v\d+\.\d+\.\d*0(\+k3s\.?1)?$`, str: "v1.12.0+k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "ibuildthecloud/k3s", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "IBuildTheCloud/K3s", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "buildthecloud/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "iibuildthecloud/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "iibuildtheclouds/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "ibuildtheclouds/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "rancher/k3s", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "ancher/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "xrancher/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "rancher-lab/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "a-rancher-org/k3s", match: false},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "Rancher/K3s", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "rancher/k3D", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "Rancher/myk3s", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "Rancher/k3docker", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "IBuildTheCloud/new-K3S-v.2", match: true},
		{re: `(?i)^((ibuildthecloud|rancher)\/.*k3(s|d).*|k3s-io\/.*)$`, str: "Rancher/myk3s", match: true},
		{re: `(?i)^((ibuildthecloud|rancher)\/.*k3(s|d).*|k3s-io\/.*)$`, str: "k3s-io/k3s", match: true},
		{re: `(?i)^((ibuildthecloud|rancher)\/.*k3(s|d).*|k3s-io\/.*)$`, str: "k3s-io/whatever", match: true},
		{re: `(?i)^(ibuildthecloud|rancher)\/.*k3(s|d).*$`, str: "k3s-io/whatever", match: false},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.0", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.1", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "1.0", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "1.2", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "2.3.0", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.0.0", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.15.0", match: true},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2", match: false},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "20", match: false},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.0.1", match: false},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "2.3.5", match: false},
		{re: `^v?\d+\.\d+(\.0)?$`, str: "v2.0.0.0", match: false},
	}
	// Execute test cases
	for index, test := range testCases {
		expected := test.match
		re := regexp.MustCompile(test.re)
		got := re.MatchString(test.str)
		if got != expected {
			t.Errorf(
				"test number %d, expected match result '%v' for string '%v' matching regexp '%v', got '%v'",
				index+1, expected, test.str, re, got,
			)
		}
	}
}