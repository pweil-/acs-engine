package certgen

import (
	"crypto/rsa"
	"crypto/x509"
	"math/big"
	"net"
	"sync"

	"github.com/Azure/acs-engine/pkg/filesystem"
)

// Config represents an OpenShift configuration
type Config struct {
	Nodes                  []Node
	ExternalRouterIP       net.IP
	ExternalMasterHostname string
	serial                 serial
	cas                    map[string]CertAndKey
	AuthSecret             string
	EncSecret              string
}

type openShiftConfig struct {
	certs       map[string]CertAndKey
	kubeconfigs map[string]KubeConfig
}

// Node represents an OpenShift node configuration
type Node struct {
	Hostname string
	IPs      []net.IP
	Master   *Master
	openShiftConfig
}

// Master represents an OpenShift master configuration
type Master struct {
	Port int16
	openShiftConfig
	etcdcerts map[string]CertAndKey
}

// CertAndKey is a certificate and key
type CertAndKey struct {
	cert *x509.Certificate
	key  *rsa.PrivateKey
}

type serial struct {
	m sync.Mutex
	i int64
}

func (s *serial) Get() *big.Int {
	s.m.Lock()
	defer s.m.Unlock()

	s.i++
	return big.NewInt(s.i)
}

func (c *Config) writeMaster(fs filesystem.Filesystem, node *Node) error {
	err := c.WriteMasterCerts(fs, node)
	if err != nil {
		return err
	}

	err = c.WriteMasterKeypair(fs, node)
	if err != nil {
		return err
	}

	err = c.WriteMasterKubeConfigs(fs, node)
	if err != nil {
		return err
	}

	err = c.WriteMasterFiles(fs, node)
	if err != nil {
		return err
	}

	return nil
}

// WriteNode writes the config for a single node to a Filesystem
func (c *Config) WriteNode(fs filesystem.Filesystem, node *Node) error {
	if node.Master != nil {
		err := c.writeMaster(fs, node)
		if err != nil {
			return err
		}
	}

	err := c.WriteNodeCerts(fs, node)
	if err != nil {
		return err
	}

	err = c.WriteNodeKubeConfig(fs, node)
	if err != nil {
		return err
	}

	err = c.WriteNodeFiles(fs, node)
	if err != nil {
		return err
	}

	return nil
}
