#requires -version 7.2
#requires -module ThreadJob

if ($IsLinux -OR $IsMacOS) {
    Return "$($PSStyle.foreground.red)This command requires a Windows platform.$($PSStyle.Reset)"
}
if ($host.name -ne 'ConsoleHost') {
    Return "$($PSStyle.foreground.red)Detected $($host.name). This command must be run from a console host.$($PSStyle.Reset)"
}
Function Get-WinEventReport {
    <#
    .SYNOPSIS
        Get an event log analysis report.
    .DESCRIPTION
        This command will analyze an event log and prepare a report showing the number of errors, warnings and information entries for each event source.
    .PARAMETER LogName
        Specify the name of an an event log like System.
    .PARAMETER MaxEvents
        Specify the maximum number of events to analyze. The default is the entire log.
    .PARAMETER Computername
        Specify the name of a computer to query. The default is the localhost.
    .PARAMETER ThrottleLimit
        This function uses thread jobs for scaling and performance. You can throttle the number of thread jobs.
    .NOTES
        This function requires a Windows platform.
        The command has an alias of wer.
    .LINK
        Get-WinEvent
    .EXAMPLE
        PS C:\> $r = Get-WinEventReport -LogName application -MaxEvents 100

        Computername: THINKX1-JH

    Logname     Source                         Total Info Warning Error
    -------     ------                         ----- ---- ------- -----
    Application dbupdate                          12   12       0     0
    Application DbxSvc                            18   13       0     5
    Application Desktop Window Manager             1    1       0     0
    Application Dolby DAX3                         4    4       0     0
    Application edgeupdate                         4    4       0     0
    Application Firefox Default Browser Agent      3    2       0     1
    Application gupdate                            7    7       0     0
    Application igccservice                        4    4       0     0
    Application igfxCUIService2.0.0.0              5    5       0     0
    Application IntelDalJhi                        1    1       0     0
    Application Microsoft-Windows-Security-SPP    15   15       0     0
    Application Microsoft-Windows-Winlogon         4    4       0     0
    Application SynTPEnhService                   17   17       0     0
    Application System Restore                     1    1       0     0
    Application VSS                                2    2       0     0
    Application Windows Error Reporting            2    2       0     0

        The number of errors and warnings will be displayed in red and yellow respectively.

    .EXAMPLE
    PS C:\ Get-WinEventReport Application -MaxEvents 5000 | Where {$_.error -gt 0 -OR $_.warning -gt 0} | format-table -view percentage


        Computername: THINKX1-JH

    LogName     Source                           Total InfoPct WarnPct ErrorPct
    -------     ------                           ----- ------- ------- --------
    Application .NET Runtime                         3   0.00%   0.00%  100.00%
    Application Application Error                    9   0.00%   0.00%  100.00%
    Application DbxSvc                             601  75.54%   0.00%   24.46%
    Application ESENT                               52  96.15%   3.85%    0.00%
    Application Firefox Default Browser Agent       85  63.53%   0.00%   36.47%
    Application Microsoft-Windows-RestartManager   220  97.27%   2.73%    0.00%
    Application Microsoft-Windows-Search            21  80.95%  19.05%    0.00%
    Application Microsoft-Windows-System-Restore    51  84.31%  15.69%    0.00%
    Application Microsoft-Windows-Winlogon          98  98.98%   1.02%    0.00%
    Application Microsoft-Windows-WMI               77  28.57%  71.43%    0.00%
    Application MsiInstaller                       380  99.21%   0.79%    0.00%
    Application VSS                                 74  68.92%   0.00%   31.08%

        Display report using the custom table view called Percentage.

    .EXAMPLE
    PS C:\> Get-WinEventReport Security | Format-Table -view security

        Computername: THINKX1-JH

    Logname  Source                              Total AuditSuccess AuditFailure
    -------  ------                              ----- ------------ ------------
    Security Microsoft-Windows-Eventlog              3            3            0
    Security Microsoft-Windows-Security-Auditing 26225        26225            0

    Use the custom table view for the security log.
    #>
    [cmdletbinding()]
    [alias('wer')]
    [OutputType('WinEventReport')]
    Param(
        [Parameter(
            Position = 0,
            Mandatory,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Specify the name of an event log like System.'
        )]
        [ValidateNotNullOrEmpty()]
        [ArgumentCompleter({
                [OutputType([System.Management.Automation.CompletionResult])]
                param(
                    [string] $CommandName,
                    [string] $ParameterName,
                    [string] $WordToComplete,
                    [System.Management.Automation.Language.CommandAst] $CommandAst,
                    [System.Collections.IDictionary] $FakeBoundParameters
                )

                $CompletionResults = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
        (Get-WinEvent -ListLog *$wordToComplete*).LogName.Foreach({
                        $CompletionResults.add($([System.Management.Automation.CompletionResult]::new("'$($_)'", $_, 'ParameterValue', $_)  ))
                    })
                return $CompletionResults
            })]
        [string]$LogName,
        [Parameter(HelpMessage = 'Specifies the maximum number of events that are returned. Enter an integer such as 100. The default is to return
        all the events in the logs or files.')]
        [Int64]$MaxEvents,
        [Parameter(
            ValueFromPipeline,
            HelpMessage = 'Specifies the name of the computer that this cmdlet gets events from the event logs.'
        )]
        [string[]]$Computername = $env:COMPUTERNAME,
        [Parameter(HelpMessage = 'This parameter limits the number of jobs running at one time. As jobs are started, they are queued and wait until a thread is available in the thread pool to run the job.')]
        [ValidateScript({ $_ -gt 0 })]
        [int]$ThrottleLimit = 5
    )
    Begin {
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ] Starting $($MyInvocation.MyCommand)"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ] Running in PowerShell $($PSVersionTable.PSVersion)"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ] Running as $($env:USERDOMAIN)\$($env:USERNAME) on $env:COMPUTERNAME"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ] Initializing a generic list"
        $JobList = [System.Collections.Generic.list[object]]::New()
    } #begin

    Process {
        Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS] Getting eventlog entries from $LogName"

        foreach ($computer in $computername) {
            #this is the job that will run remotely
            $job = {
                Param($LogName, $MaxEvents, $computername)
                #match verbose preference from the source host
                $VerbosePreference = $using:VerbosePreference

                #remove MaxEvents if there is no value passed
                if ($PSBoundParameters['MaxEvents'] -le 1) {
                    [void]$PSBoundParameters.Remove('MaxEvents')
                }
                Try {
                    Write-Verbose "[$((Get-Date).TimeOfDay) THREAD ] Querying $($($PSBoundParameters)['LogName']) on $($PSBoundParameters['Computername'].ToUpper())"
                    $logs = Get-WinEvent @PSBoundParameters -ErrorAction Stop | Group-Object ProviderName
                    $LogCount = ($logs | Measure-Object -Property Count -Sum).sum
                    Write-Verbose "[$((Get-Date).TimeOfDay) THREAD ] Retrieved $($logs.count) event sources from $LogCount records."
                    Write-Verbose "[$((Get-Date).TimeOfDay) THREAD ] Detected log $($logs[0].group[0].LogName)"
                    $logs.foreach({
                            if ( $_.group[0].LogName -eq 'Security') {
                                $AS = (($_.group).where({ $_.keywordsDisplayNames[0] -match 'Success' }).count)
                                $AF = (($_.group).where({ $_.keywordsDisplayNames[0] -match 'Failure' }).count)
                            }
                            else {
                                $AS = 0
                                $AF = 0
                            }

                            $report = [PSCustomObject]@{
                                PSTypename   = 'WinEventReport'
                                LogName      = $_.group[0].LogName
                                Source       = $_.Name
                                Total        = $_.Count
                                Information  = (($_.group).where({ $_.level -eq 4 }).count)
                                Warning      = (($_.group).where({ $_.level -eq 3 }).count)
                                Error        = (($_.group).where({ $_.level -eq 2 }).count)
                                AuditSuccess = $AS
                                AuditFailure = $AF
                                ComputerName = $PSBoundParameters['Computername'].ToUpper()
                                AuditDate    = (Get-Date)
                            }
                            $report
                        })
                } #Try
                Catch {
                    throw "Failed to query $($PSBoundParameters['Computername'].ToUpper()).$($_.Exception.Message)"
                }
                Write-Verbose "[$((Get-Date).TimeOfDay) THREAD ] Finished processing $($PSBoundParameters['Computername'].ToUpper())"
            }

            $JobList.Add((Start-ThreadJob -Name $computer -ScriptBlock $job -ArgumentList $LogName, $MaxEvents, $computer -ThrottleLimit $ThrottleLimit))
        } #foreach computer
    } #process

    End {
        $count = $JobList.count
        do {
            Write-Verbose "[$((Get-Date).TimeOfDay) END    ] Waiting for jobs to finish: $( $JobList.Where({$_.state -notmatch 'completed|failed'}).Name -join ',')"
            [string[]]$waiting = $JobList.Where({ $_.state -notmatch 'completed|failed' }).Name
            if ($waiting.count -gt 0) {
                #write-progress doesn't display right at 0%
                if ($waiting.count -eq $count) {
                    [int]$pc = 5
                }
                else {
                    [int]$pc = (100 - ($waiting.count / $count) * 100)
                }
                Write-Progress -Activity "Waiting for $($JobList.count) jobs to complete." -Status "$($waiting -join ',') $pc%" -PercentComplete $pc
            }
            $JobList.Where({ $_.state -match 'completed|failed' }) | ForEach-Object { Receive-Job $_.id -Keep ; [void]$JobList.remove($_) }
            #wait 1 second before checking again
            Start-Sleep -Milliseconds 1000
        } while ($JobList.count -gt 0)

        if ($JobList.state -contains 'failed') {
            $JobList.Where({ $_.state -match 'failed' }) | ForEach-Object {
                $msg = '[{0}] Failed. {1}' -f $_.Name.toUpper(), ((Get-Job -Id $_.id).ChildJobs.JobStateInfo.Reason.Message)
                Write-Warning $msg
            }
        }
        #ThreadJob remain with results so you can retrieve data again.
        #You can manually remove the jobs.
        Write-Verbose "[$((Get-Date).TimeOfDay) END    ] Ending $($MyInvocation.MyCommand)"
    } #end

} #close Get-WinEventReport

#region format and type data
<#
Import the custom formatting file. It is expected to be in the same
directory as this script file. If querying the Security log you will want
to use the custom view.

Get-WinEventReport 'Security' -MaxEvents 1000 -Computername DOM1,DOM2 | format-table -View security

#>

Update-FormatData $PSScriptRoot\WinEventReport.format.ps1xml

#extend the type by adding an alias property
Update-TypeData -TypeName WinEventReport -MemberType AliasProperty -MemberName Date -Value AuditDate -force

#endregion