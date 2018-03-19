package certgen

import (
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/Azure/acs-engine/pkg/filesystem"
	"gopkg.in/yaml.v2"
)

// KubeConfig represents a kubeconfig
type KubeConfig struct {
	APIVersion     string                 `yaml:"apiVersion,omitempty"`
	Kind           string                 `yaml:"kind,omitempty"`
	Clusters       []Cluster              `yaml:"clusters,omitempty"`
	Contexts       []Context              `yaml:"contexts,omitempty"`
	CurrentContext string                 `yaml:"current-context,omitempty"`
	Preferences    map[string]interface{} `yaml:"preferences,omitempty"`
	Users          []User                 `yaml:"users,omitempty"`
}

// Cluster represents a kubeconfig cluster
type Cluster struct {
	Name    string      `yaml:"name,omitempty"`
	Cluster ClusterInfo `yaml:"cluster,omitempty"`
}

// ClusterInfo represents a kubeconfig clusterinfo
type ClusterInfo struct {
	Server                   string `yaml:"server,omitempty"`
	CertificateAuthorityData string `yaml:"certificate-authority-data,omitempty"`
}

// Context represents a kubeconfig context
type Context struct {
	Name    string      `yaml:"name,omitempty"`
	Context ContextInfo `yaml:"context,omitempty"`
}

// ContextInfo represents a kubeconfig contextinfo
type ContextInfo struct {
	Cluster   string `yaml:"cluster,omitempty"`
	Namespace string `yaml:"namespace,omitempty"`
	User      string `yaml:"user,omitempty"`
}

// User represents a kubeconfig user
type User struct {
	Name string   `yaml:"name,omitempty"`
	User UserInfo `yaml:"user,omitempty"`
}

// UserInfo represents a kubeconfig userinfo
type UserInfo struct {
	ClientCertificateData string `yaml:"client-certificate-data,omitempty"`
	ClientKeyData         string `yaml:"client-key-data,omitempty"`
}

// PrepareMasterKubeConfigs creates the master kubeconfigs
func (c *Config) PrepareMasterKubeConfigs(node *Node) error {
	endpoint := fmt.Sprintf("%s:%d", node.Hostname, node.Master.Port)
	endpointName := strings.Replace(endpoint, ".", "-", -1)

	externalEndpoint := fmt.Sprintf("%s:%d", c.ExternalMasterHostname, node.Master.Port)
	externalEndpointName := strings.Replace(externalEndpoint, ".", "-", -1)

	localhostEndpoint := fmt.Sprintf("localhost:%d", node.Master.Port)
	localhostEndpointName := strings.Replace(localhostEndpoint, ".", "-", -1)

	cacert, err := certAsBytes(c.cas["ca"].cert)
	if err != nil {
		return err
	}
	admincert, err := certAsBytes(node.Master.certs["admin"].cert)
	if err != nil {
		return err
	}
	adminkey, err := privateKeyAsBytes(node.Master.certs["admin"].key)
	if err != nil {
		return err
	}
	mastercert, err := certAsBytes(node.Master.certs["openshift-master"].cert)
	if err != nil {
		return err
	}
	masterkey, err := privateKeyAsBytes(node.Master.certs["openshift-master"].key)
	if err != nil {
		return err
	}
	aggregatorcert, err := certAsBytes(node.Master.certs["aggregator-front-proxy"].cert)
	if err != nil {
		return err
	}
	aggregatorkey, err := privateKeyAsBytes(node.Master.certs["aggregator-front-proxy"].key)
	if err != nil {
		return err
	}

	node.Master.kubeconfigs = map[string]KubeConfig{
		"admin.kubeconfig": {
			APIVersion: "v1",
			Kind:       "Config",
			Clusters: []Cluster{
				{
					Name: externalEndpointName,
					Cluster: ClusterInfo{
						Server: fmt.Sprintf("https://%s", externalEndpoint),
						CertificateAuthorityData: base64.StdEncoding.EncodeToString(cacert),
					},
				},
			},
			Contexts: []Context{
				{
					Name: fmt.Sprintf("default/%s/system:admin", externalEndpointName),
					Context: ContextInfo{
						Cluster:   externalEndpointName,
						Namespace: "default",
						User:      fmt.Sprintf("system:admin/%s", externalEndpointName),
					},
				},
			},
			CurrentContext: fmt.Sprintf("default/%s/system:admin", externalEndpointName),
			Users: []User{
				{
					Name: fmt.Sprintf("system:admin/%s", externalEndpointName),
					User: UserInfo{
						ClientCertificateData: base64.StdEncoding.EncodeToString(admincert),
						ClientKeyData:         base64.StdEncoding.EncodeToString(adminkey),
					},
				},
			},
		},
		"aggregator-front-proxy.kubeconfig": {
			APIVersion: "v1",
			Kind:       "Config",
			Clusters: []Cluster{
				{
					Name: localhostEndpointName,
					Cluster: ClusterInfo{
						Server: fmt.Sprintf("https://%s", localhostEndpoint),
						CertificateAuthorityData: base64.StdEncoding.EncodeToString(cacert),
					},
				},
			},
			Contexts: []Context{
				{
					Name: fmt.Sprintf("default/%s/aggregator-front-proxy", localhostEndpointName),
					Context: ContextInfo{
						Cluster:   localhostEndpointName,
						Namespace: "default",
						User:      fmt.Sprintf("aggregator-front-proxy/%s", localhostEndpointName),
					},
				},
			},
			CurrentContext: fmt.Sprintf("default/%s/aggregator-front-proxy", localhostEndpointName),
			Users: []User{
				{
					Name: fmt.Sprintf("aggregator-front-proxy/%s", localhostEndpointName),
					User: UserInfo{
						ClientCertificateData: base64.StdEncoding.EncodeToString(aggregatorcert),
						ClientKeyData:         base64.StdEncoding.EncodeToString(aggregatorkey),
					},
				},
			},
		},
		"openshift-master.kubeconfig": {
			APIVersion: "v1",
			Kind:       "Config",
			Clusters: []Cluster{
				{
					Name: endpointName,
					Cluster: ClusterInfo{
						Server: fmt.Sprintf("https://%s", endpoint),
						CertificateAuthorityData: base64.StdEncoding.EncodeToString(cacert),
					},
				},
			},
			Contexts: []Context{
				{
					Name: fmt.Sprintf("default/%s/system:openshift-master", endpointName),
					Context: ContextInfo{
						Cluster:   endpointName,
						Namespace: "default",
						User:      fmt.Sprintf("system:openshift-master/%s", endpointName),
					},
				},
			},
			CurrentContext: fmt.Sprintf("default/%s/system:openshift-master", endpointName),
			Users: []User{
				{
					Name: fmt.Sprintf("system:openshift-master/%s", endpointName),
					User: UserInfo{
						ClientCertificateData: base64.StdEncoding.EncodeToString(mastercert),
						ClientKeyData:         base64.StdEncoding.EncodeToString(masterkey),
					},
				},
			},
		},
	}

	return nil
}

// PrepareNodeKubeConfig creates the node kubeconfig
func (c *Config) PrepareNodeKubeConfig(node *Node) error {
	ep := fmt.Sprintf("%s:%d", c.ExternalMasterHostname, c.Nodes[0].Master.Port)
	epName := strings.Replace(ep, ".", "-", -1)

	cacert, err := certAsBytes(c.cas["ca"].cert)
	if err != nil {
		return err
	}
	masterclientcert, err := certAsBytes(node.certs[fmt.Sprintf("system:node:%s", node.Hostname)].cert)
	if err != nil {
		return err
	}
	masterclientkey, err := privateKeyAsBytes(node.certs[fmt.Sprintf("system:node:%s", node.Hostname)].key)
	if err != nil {
		return err
	}

	bootstrapCert, err := certAsBytes(c.Nodes[0].Master.certs["node-bootstrapper"].cert)
	if err != nil {
		return err
	}
	bootstrapKey, err := privateKeyAsBytes(c.Nodes[0].Master.certs["node-bootstrapper"].key)
	if err != nil {
		return err
	}

	node.kubeconfigs = map[string]KubeConfig{
		fmt.Sprintf("system:node:%s.kubeconfig", node.Hostname): {
			APIVersion: "v1",
			Kind:       "Config",
			Clusters: []Cluster{
				{
					Name: epName,
					Cluster: ClusterInfo{
						Server: fmt.Sprintf("https://%s", ep),
						CertificateAuthorityData: base64.StdEncoding.EncodeToString(cacert),
					},
				},
			},
			Contexts: []Context{
				{
					Name: fmt.Sprintf("default/%s/system:node:%s", epName, node.Hostname),
					Context: ContextInfo{
						Cluster:   epName,
						Namespace: "default",
						User:      fmt.Sprintf("system:node:%s/%s", node.Hostname, epName),
					},
				},
			},
			CurrentContext: fmt.Sprintf("default/%s/system:node:%s", epName, node.Hostname),
			Users: []User{
				{
					Name: fmt.Sprintf("system:node:%s/%s", node.Hostname, epName),
					User: UserInfo{
						ClientCertificateData: base64.StdEncoding.EncodeToString(masterclientcert),
						ClientKeyData:         base64.StdEncoding.EncodeToString(masterclientkey),
					},
				},
			},
		},
		"bootstrap.kubeconfig": {
			APIVersion: "v1",
			Kind:       "Config",
			Clusters: []Cluster{
				{
					Name: epName,
					Cluster: ClusterInfo{
						Server: fmt.Sprintf("https://%s", ep),
						CertificateAuthorityData: base64.StdEncoding.EncodeToString(cacert),
					},
				},
			},
			Contexts: []Context{
				{
					Name: fmt.Sprintf("default/%s/system:serviceaccount:openshift-infra:node-bootstrapper", epName),
					Context: ContextInfo{
						Cluster:   epName,
						Namespace: "default",
						User:      fmt.Sprintf("system:serviceaccount:openshift-infra:node-bootstrapper/%s", epName),
					},
				},
			},
			CurrentContext: fmt.Sprintf("default/%s/system:serviceaccount:openshift-infra:node-bootstrapper", epName),
			Users: []User{
				{
					Name: fmt.Sprintf("system:serviceaccount:openshift-infra:node-bootstrapper/%s", epName),
					User: UserInfo{
						ClientCertificateData: base64.StdEncoding.EncodeToString(bootstrapCert),
						ClientKeyData:         base64.StdEncoding.EncodeToString(bootstrapKey),
					},
				},
			},
		},
	}

	return nil
}

// WriteMasterKubeConfigs writes the master kubeconfigs
func (c *Config) WriteMasterKubeConfigs(fs filesystem.Filesystem, node *Node) error {
	for filename, kubeconfig := range node.Master.kubeconfigs {
		b, err := yaml.Marshal(&kubeconfig)
		if err != nil {
			return err
		}
		err = fs.WriteFile(fmt.Sprintf("etc/origin/master/%s", filename), b, 0600)
		if err != nil {
			return err
		}
	}

	return nil
}

// WriteNodeKubeConfig writes the node kubeconfig
func (c *Config) WriteNodeKubeConfig(fs filesystem.Filesystem, node *Node) error {
	for filename, kubeconfig := range node.kubeconfigs {
		b, err := yaml.Marshal(&kubeconfig)
		if err != nil {
			return err
		}
		err = fs.WriteFile(fmt.Sprintf("etc/origin/node/%s", filename), b, 0600)
		if err != nil {
			return err
		}
	}

	return nil
}
