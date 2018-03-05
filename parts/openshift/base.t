{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",

    {{/* parameters section contains ??? */}}
    "parameters": {
        {{template "openshift/params.t" .}}
    },

    {{/* variables section contains ??? */}}
    "variables": {
        {{template "openshift/vars.t" .}}
    },

    {{/* resources section contains ??? */}}
    "resources": [
        {{ template "openshift/resources.t" .}}
    ],

    {{/* outputs section contains ??? */}}
    "outputs": {
        {{ template "openshift/outputs.t" .}}
    }
}
