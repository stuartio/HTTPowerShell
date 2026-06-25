# HTTP Powershell

User-friendly web client written in PowerShell. This is client is based on the excellent httpie, but using only PowerShell/DotNet components. It acts largely as a wrapper around Invoke-WebRequest, and supports all parameters of that cmdlet in addition to the additional parameters presented.

## Installation

You can either install the module directly from the PowerShell Gallery

```powershell
Install-Module httpowershell
```

or clone this repo and import manually

```powershell
Import-Module ./HTTPowershell.psd1
```

## Usage

Once imported there is a single public function named `Invoke-HTTP` which is aliased to `web` for simplicity. The alias will be used in all examples, becuase I think it is cooler :-) .

The simplest use case to make a request requires just this

```powershell
web httpbin.org
```

This will perform a GET request against the above URL and display the status code, response headers and response body. It will also assume the protocol to be https://, because it usually is in these fancy, modern times. If you specify the protocol, this is fine, too. And you can also specify plain http if required.

> Note: the Uri is the only positional parameter, so unless you add the -Uri parameter name it must come before any other, unnamed, parameter values.

### Adding Request Headers

Request headers can be added anywhere in the command by use of the `key:value` combination, like this:

```powershell
web https://httpbin.org/ accept:*.* user-agent:httpowershell
```

> Strings do not need to be quoted unless they contain PowerShell control characters, such as semi-colon (;) or ampersand (&). For safety, quoting the whole string or either part of it is fine.

> Note: Headers can be placed anywhere in the command, _after_ the URL (unless -Uri is specified), and do not need to be kept together, i.e. you can intersperse header values with query parameters, cookies or anything else.

### Adding Query String Params

Query string parameters can be added anywhere in the command by the use of the `key=value` combination, like this:

```powershell
web https://httpbin.org/ include=yes deny=no
```

This will result in a request Uri of `https://httpbin.org/?include=yes&deny=no`. You can also combine query parameters specified in this way and included in the Uri, like this:

```powershell
web https://httpbin.org/?one=1&two=2 include=yes deny=no
```

In this case the resulting Uri would be `https://httpbin.org/?one=1&two=2&include=yes&deny=no`

> Strings do not need to be quoted unless they contain PowerShell control characters, such as semi-colon (;) or ampersand (&). For safety, quoting the whole string or either part of it is fine.

### Adding Request Cookies

Request cookies can be added anywhere in the command by the use of the `key==value` combination (note the double `=`), like this:

```powershell
web https://httpbin.org/ session==12345
```

> Strings do not need to be quoted unless they contain PowerShell control characters, such as semi-colon (;) or ampersand (&). For safety, quoting the whole string or either part of it is fine.

## Configuring the display

By default, HTTPowershell will display response status, headers and body. You can configure this by the use of the `-Display` or `-d` parameter. It can contain one or more of the following options

- `H` - Request headers
- `B` - Request body
- `s` - Response status code, e.g. `200`
- `S` - Response status code with description, e.g. `200 OK`
- `h` - Response headers
- `b` - Response body as formatted string
- `j` - Response body converted from JSON to PSCustomObject
- `x` - Response body converted from XML to PSCustomObject

For example:

```powershell
# Display default response status, headers and body
web https://httpbin.org/ -Display shb
```

```powershell
# Display request url and headers
web https://httpbin.org/ -Display H
```

```powershell
# Display response body only
web https://httpbin.org/ -d b
```

```powershell
# Display response body as object
web https://httpbin.org/ -d j
```

### Limiting the displayed headers

Often, the number of response headers can be quite large, and you may only be interested in a small number. You can use methods like `Select-String` to filter the output, but combining multiple headers, _and_ the status and perhaps even the response body into a single `Select-String` pattern can be problematic, so we have added an option to limit the displayed headers with `-DisplayHeaders` and an array of strings.

For example:

```powershell
web www.example.com -Display sh -DisplayHeaders server, content-type
```

### Handling multi-part response bodies

When you receive a response which uses a Content type similar to "multipart/form-data", the response is broken out in multiple "parts", each with headers and body elements. HTTPowerShell allows you to specify which of these parts to display, which are then further filtered by your use of the -Display parameter. For example, if you want to display only the headers of the second part of a response, for example when using Akamai EdgeWorkers' Response Provider feature, you can do this with

```powershell
web https://httpbin.org/ -Display sh -DisplayParts 1
```

## Handling authentication

HTTPowerShell allows you to authenticate your client in several ways.

### Basic authentication

Using the mechanism provided in Invoke-WebRequest, which is the function Invoke-HTTP eventually calls, you can use basic auth like this:

```powershell
$username = "myuser"
$password = "mypassword"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

web "www.example.com" -Authentication Basic -Credential $credential
```

### Akamai EdgeGrid

If you are using HTTPowerShell to authenticate to Akamai Edgegrid APIs you can do so natively, without install the Akamai PowerShell modules. Essentially, when you specify the auth type as `edgegrid` Invoke-HTTP dynamically adds 3 additional parameters: `EdgeRCFile`, `Section` and `AccountSwitchKey`.

Also, when using EdgeGrid authentication you do not need to provide the protocol or hostname in your request URI, as these are inferred from your credentials.

For example:

```powershell
# Make a request using the default location for your .edgerc file (~/.edgerc) and the 'default' section
web /papi/v1/contracts -Authentication EdgeGrid
```

```powershell
# Make a request using a custom .edgerc location and section
web /papi/v1/contracts -Authentication EdgeGrid -EdgeRCFile /path/to/my.edgerc -Section other
```

```powershell
# Make a request using a custom .edgerc location and section, and an account switch key
web /papi/v1/contracts -Authentication EdgeGrid -EdgeRCFile /path/to/my.edgerc -Section other -AccountSwitchKey 1-2AB34C
```

### Mutual TLS / Client Certificates

HTTPowerShell supports client certificates in several ways. You can provide your base64-encoded PEM certificate and key as either strings or file paths, and Windows users can use the Windows Certificate Store in the same way as with Invoke-WebRequest.

For example:

```powershell
# Specify the pem and key files for your client certificate
web www.example.com -ClientCertificateFile mycert.pem -ClientKeyFile mycert.key
```

```powershell
# Specify the pem and key of your client certificate as strings
$MyCert = "---BEGIN CERTIFICATE---<pem data>---END CERTIFICATE---"
$MyKey = "---BEGIN RSA PRIVATE KEY---<key data>---END RSA PRIVATE KEY---"
web www.example.com -ClientCertificate $MyCert -ClientKey $MyKey
```

```powershell
# Windows only - Use cert from Windows Certificate Store
$MyCert = gci Cert:\CurrentUser\My\ | Where-Object { 'Client Authentication' -in $_.EnhancedKeyUsageList.FriendlyName }
web www.example.com -CertificateThumbprint $MyCert.Thumbprint
```

## Specifying the HTTP Version

HTTPowershell allows you to specify which version of HTTP you wish to use. For example,

```powershell
# Force HTTP 1.0
web www.google.com -Http1
```

```powershell
# Force HTTP 1.1
web www.google.com -Http11
```

```powershell
# Force HTTP 2
web www.google.com -Http2
```

```powershell
# Force HTTP 3
web www.google.com -Http3
```

## Resolving to a different IP

Occasionally, it is useful to force a request to a different IP, for example if you need to bypass a load balancer and hit a server directly. You can do this with HTTPowerShel with the -Resolve option, which replaces the hostname used to make the underlying HTTP request, while maintaining the hostname in your -Uri as the forward host header, and as the SNI servername header.

> Note: Since the forward SNI server name is the original hostname (not the resolved one), then you may face an issue that the presented TLS certificate of the new server is invalid. If this is OK you can use the -SkipCertificateCheck to bypass the TLS error and proceed. However, this option should be used only when you are sure the receiving server is trustworthy.

For example:

```powershell
# To connect to origin.example.com instead of www.example.com
web www.example.com -Resolve origin.example.com
```

If you are working with Akamai, you can also use this feature as a short cut to access the Akamai Staging network. This is a subset of the Akamai network to which configurarions can be deployed, allowing you to test away from impacting your users, but to access it typically requires editing your hosts file. HTTPowerShell handles this for you by making its own DNS lookup (using Google's public DoH servers), and resolving to staging.

> Note: As this feature requires DNS resolution it will incur a performance penalty and requires that the CNAME chain be visible in DNS, i.e. no CNAME collapsing features such as Zone Apex Mapping are employed.

To use this, you can set -Resolve to literally 'AkamaiStaging' (the casing is unimportant, like this:

```powershell
web www.example.com -Resolve AkamaiStaging
```

> Look for the X-Akamai-Staging header in the response to indicate you are using the staging network. If this header does not appear it is possible something is misconfigured, or perhaps you are using a proxy.