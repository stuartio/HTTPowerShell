# HTTP Powershell

User-friendly web client written in PowerShell. This is client is based on the excellent httpie, but using only PowerShell/DotNet components. It acts largely as a wrapper around Invoke-WebRequest, and supports all parameters of that cmdlet in addition to the additional parameters presented.

## Installation

You can either install the module directly from the PowerShell Gallery

```powershell
Install-Module httpowershell
```

or clone this repo and import manually

```powershell
Import-Module src/HTTPowershell
```

## Usage

Once imported there is a single public function named `Invoke-HTTP` which is aliased to `web` for simplicity. The alias will be used in all examples, becuase I think it is cooler :-) .

The simplest use case to make a request simply requires, like this

```powershell
web https://httpbin.org
```

This will perform a GET request against the above URL and display the status code, response headers and response body.

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

```
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