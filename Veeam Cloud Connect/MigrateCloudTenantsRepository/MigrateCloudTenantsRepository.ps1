##################################################################
#                   User Defined Variables
##################################################################


# Names of tenant accounts separated by comma (Mandatory)
# For instance, $TenantsForMigration = @("Tenant1", "Tenant2")
# 
# Requirements:
# Tenants running Veeam Backup and Replication version older than 9.5 are not supported for migration
# Tenants with special characters in their names are not supported for migration

$TenantsForMigration = @(
    "GuillermoR"#,
    #"Tenant2"
)

# Name of Scale-Out Backup Repository tenants backups should be migrated to
# For instance, $ScaleOutRepositoryName = "sobr"
# Requirements:
# Extents cannot be in maintenance mode

$ScaleOutRepositoryName = "SOBR01"


##################################################################
#                   End User Defined Variables
##################################################################

#################### DO NOT MODIFY PAST THIS LINE ################

add-pssnapin veeampssnapin


function SwitchVBRCloudTenantsQuotasRepository()
{
	[CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Veeam.Backup.PowerShell.Infos.IVBRCloudTenant[]] $Tenants,
        
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Veeam.Backup.PowerShell.Infos.VBRScaleOutBackupRepository] $Repository = $(throw "Scale Out Backup Repository required.")
    )
    
    Write-Output "Validating tenants and target repository"
    $validationResult = Validate-VBRCloudTenantQuota -Tenants $tenants -ScaleOutBackupRepository $Repository
    
    if ($validationResult.ValidTenants.Length -ne 0)
    {
        Write-Output "Valid tenants:"

        foreach($tenant in $validationResult.ValidTenants)
        {
            Write-Output $tenant.Name
        }
        
        Write-Output ""
    }

    if ($validationResult.HasErrors)
    {
        if ($validationResult.RepositoryErrors.Length -ne 0)
        {
            Write-Warning "Repository errors:"

            foreach($error in $validationResult.RepositoryErrors)
            {
                Write-Output $error
            }
        
            Write-Output ""
        }

        if ($validationResult.TenantsErrors.Length -ne 0)
        {
            Write-Warning "Tenants errors:"
        
            foreach($tenantErrors in $validationResult.TenantsErrors.GetEnumerator())
            {
                $tenantName = $tenantErrors.Key.Name
                Write-Output "$tenantName"

                foreach($error in $tenantErrors.Value)
                {
                    Write-Output "    $error"
                }
                
                Write-Output ""
            }
        }

        #In case of one or multiple failures additional confirmation dialog box is shown

        $title = "Tenant backups' migration"
        $message = "Start migration process?"

        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes"
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No"

        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        $result = $host.ui.PromptForChoice($title, $message, $options, 0) 
    }


    if ($validationResult.ValidTenants.Length -ne 0)
    {
        if($result -ne 1)
        {
            Write-Output "Tenants were validated. Starting migration process..."
            $switchingResult = Switch-VBRCloudTenantQuotaRepository -Tenants $validationResult.ValidTenants -ScaleOutBackupRepository $Repository -WaitRescan
            
            if ($switchingResult.ProcessedTenants.Length -ne 0)
            {
                Write-Output "The following tenants were processed:"
                
                foreach($tenant in $switchingResult.ProcessedTenants)
                {
                    Write-Output $tenant.Name
                }
            
                Write-Output ""
            }
            
            if ($switchingResult.TenantsWithErrors.Length -ne 0)
            {
                Write-Warning "The following tenants had one or several issues associated with them and were skipped from processing:"
                
                foreach($tenant in $switchingResult.TenantsWithErrors)
                {
                    Write-Output $tenant.Name
                }
            
                Write-Output ""
            }
            
            if ($switchingResult.StoragesErrors.Length -ne 0)
            {
                Write-Warning "Could not find the following storages:"
                
                foreach($storageError in $switchingResult.StoragesErrors)
                {
                    Write-Output $tenant.Name
                }
            
                Write-Output ""
            }
            Write-Warning "Do not rescan old repository that hosted tenants' backup and backup metadata files, before you remove from it tenants' backup and backup metadata files that were migrated to the Scale-Out Repository. Otherwise, multiple issues are expected."
        }
        else
        {
            break;
        }
    }
        else
        {
            Write-Warning "No valid tenants to update."
        }
        
    Write-Output "Finish."
}

##########

Write-Output "Loading tenants list"
$tenants = Get-VBRCloudTenant -Name $TenantsForMigration -ErrorVariable TenantsErrors -ErrorAction SilentlyContinue
if($TenantsErrors)
{
    "$($TenantsErrors.Count) errors encountered:"
    
    foreach ($e in $TenantsErrors.GetEnumerator())
    {
        $e.Exception # errors list
    }
}
$sobr = Get-VBRBackupRepository -Name $ScaleOutRepositoryName -ScaleOut
 if ($sobr.Count -eq 0){
     $RepositoryErrors = 1
     Write-Output "Failed to find repository: $ScaleOutRepositoryName"   
}

if ($TenantsErrors.Count + $RepositoryErrors -eq 0)
{
    SwitchVBRCloudTenantsQuotasRepository $tenants $sobr
}