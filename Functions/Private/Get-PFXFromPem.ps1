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
        $ClientKeyFile
    )

    process {
        if ($ClientCertificate) {
            $CertificateContent = $ClientCertificate
        }
        elseif ($ClientCertificateFile) {
            if (-not (Test-Path $ClientCertificateFile)) {
                Write-Error "ClientCertificateFile '$ClientCertificateFile' not found"
                return
            }
            $CertificateContent = Get-Content -Raw -Path $ClientCertificateFile
        }
        if ($ClientKey) {
            $KeyContent = $ClientKey
        }
        elseif ($ClientKeyFile) {
            if (-not (Test-Path $ClientKeyFile)) {
                Write-Error "ClientKeyFile '$ClientKeyFile' not found"
                return
            }
            $KeyContent = Get-Content -Raw -Path $ClientKeyFile
        }
    
    
        $PemCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($CertificateContent, $KeyContent)
        $PFXBytes = $PemCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
        $PFX = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PFXBytes)
    
        return $PFX
    }
}