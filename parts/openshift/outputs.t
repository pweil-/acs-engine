    "Openshift Webconsole" : {
      "type" : "string",
      "value" : "[concat('https://', reference(resourceGroup().name).dnsSettings.fqdn, ':8443/console')]"
    },
    "Bastion ssh" : {
      "type" : "string",
      "value" : "[concat('ssh -A ', reference('bastion').outputs.fqdn.value)]"
    },
    "Openshift Router Public IP" : {
      "type" : "string",
      "value" : "[reference(parameters('WildcardZone')).ipAddress]"
    }
