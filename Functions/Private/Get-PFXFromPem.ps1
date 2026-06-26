function Get-PFXFromPem {
    Param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientCertificate,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientCertificateFile,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientKey,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientKeyFile,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $ClientKeyPassword
    )

    process {
        if ($ClientCertificate) {
            $CertificateContent = $ClientCertificate
        }
        elseif ($ClientCertificateFile) {
            if (-not (Test-Path $ClientCertificateFile)) {
                Write-Error "Client certificate file '$ClientCertificateFile' not found"
                return
            }
            Write-Debug "Reading certificate from file: $ClientCertificateFile"
            $CertificateContent = Get-Content -Raw -Path $ClientCertificateFile
        }
        if ($ClientKey) {
            $KeyContent = $ClientKey
        }
        elseif ($ClientKeyFile) {
            if (-not (Test-Path $ClientKeyFile)) {
                Write-Error "Client key file '$ClientKeyFile' not found"
                return
            }
            Write-Debug "Reading key from file: $ClientKeyFile"
            $KeyContent = Get-Content -Raw -Path $ClientKeyFile
        }

        # Validate we have both elements
        if (-not ($CertificateContent -and $KeyContent)) {
            throw "Both client certificate and key are required for mutual TLS."
        }

        # Handle encrypted keys differently
        if ($KeyContent.StartsWith("-----BEGIN ENCRYPTED PRIVATE KEY-----")) {
            if (-not $ClientKeyPassword) {
                $ClientKeyPasswordSec = Read-Host -Prompt "Enter password for encrypted key" -AsSecureString
                $ClientKeyPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientKeyPasswordSec))
            }
            $PemCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromEncryptedPem($CertificateContent, $KeyContent, $ClientKeyPassword)
        }
        else {
            $PemCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($CertificateContent, $KeyContent)
        }
    
        $PFXBytes = $PemCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
        $PFX = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PFXBytes)
    
        return $PFX
    }
}