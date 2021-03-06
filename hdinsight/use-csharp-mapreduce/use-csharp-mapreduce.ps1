function Start-MapReduce {
    # Script should stop on failures
    $ErrorActionPreference = "Stop"
    
    # Login to your Azure subscription
    # Is there an active Azure subscription?
    $sub = Get-AzureRmSubscription -ErrorAction SilentlyContinue
    if(-not($sub))
    {
        Add-AzureRmAccount
    }

    # Get HDInsight info
    $clusterName = Read-Host -Prompt "Enter the HDInsight cluster name"
    $creds=Get-Credential -Message "Enter the login for the cluster"

    # Path for job output
    $outputPath="/example/wordcountoutput"

    # Progress indicator
    $activity="C# MapReduce example"
    Write-Progress -Activity $activity -Status "Getting cluster information..."
    #Get HDInsight info so we can get the resource group, storage, etc.
    $clusterInfo = Get-AzureRmHDInsightCluster -ClusterName $clusterName
    $resourceGroup = $clusterInfo.ResourceGroup
    $storageActArr=$clusterInfo.DefaultStorageAccount.split('.')
    $storageAccountName=$storageActArr[0]
    $storageType=$storageActArr[1]
    
    # Progress indicator
    #Define the MapReduce job
    # Note: using "/mapper.exe" and "/reducer.exe" looks in the root
    #       of default storage.
    $jobDef=New-AzureRmHDInsightStreamingMapReduceJobDefinition `
        -Files "/mapper.exe","/reducer.exe" `
        -Mapper "mapper.exe" `
        -Reducer "reducer.exe" `
        -InputPath "/example/data/gutenberg/davinci.txt" `
        -OutputPath $outputPath

    # Start the job
    Write-Progress -Activity $activity -Status "Starting MapReduce job..."
    $job=Start-AzureRmHDInsightJob `
        -ClusterName $clusterName `
        -JobDefinition $jobDef `
        -HttpCredential $creds

    #Wait for the job to complete
    Write-Progress -Activity $activity -Status "Waiting for the job to complete..."
    Wait-AzureRmHDInsightJob `
        -ClusterName $clusterName `
        -JobId $job.JobId `
        -HttpCredential $creds

    Write-Progress -Activity $activity -Completed

    # Download the output 
    if($storageType -eq 'azuredatalakestore') {
        # Azure Data Lake Store
        # Fie path is the root of the HDInsight storage + $outputPath
        $filePath=$clusterInfo.DefaultStorageRootPath + $outputPath + "/part-00000"
        Export-AzureRmDataLakeStoreItem `
            -Account $storageAccountName `
            -Path $filePath `
            -Destination output.txt
    } else {
        # Azure Storage account
        # Get the container
        $container=$clusterInfo.DefaultStorageContainer
        #NOTE: This assumes that the storage account is in the same resource
        #      group as HDInsight. If it is not, change the
        #      --ResourceGroupName parameter to the group that contains storage.
        $storageAccountKey=(Get-AzureRmStorageAccountKey `
            -Name $storageAccountName `
        -ResourceGroupName $resourceGroup)[0].Value

        #Create a storage context
        $context = New-AzureStorageContext `
            -StorageAccountName $storageAccountName `
            -StorageAccountKey $storageAccountKey
        # Download the file
        Get-AzureStorageBlobContent `
            -Blob 'example/wordcountoutput/part-00000' `
            -Container $container `
            -Destination output.txt `
            -Context $context
    }
}