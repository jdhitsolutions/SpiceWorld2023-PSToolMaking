
BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'Get-WinEventReport' {
    BeforeAll {
        $help = Get-Help Get-WinEvent
        $cmd = Get-Command -name Get-WinEventReport
    }
    Context Parameters {
        It 'Should support common parameters' {
            (Get-Item Function:\Get-WinEventReport).parameters.ContainsKey('ErrorAction')
        }

        It 'Should require a log name' {
            $cmd.Parameters['LogName'].Attributes.Where({ $_.TypeID.name -match 'ParameterAttribute' }).Mandatory
        }
        It 'Should take a log name from the pipeline by property name' {
            $cmd.Parameters['LogName'].Attributes.Where({ $_.TypeID.name -match 'ParameterAttribute' }).ValueFromPipelineByPropertyName
        }
        It 'The LogName parameter should be positional' {

        } -pending
        It 'Should let the user specify the maximum number of events' {

        } -Pending
        It 'Should let the user specify a computer name' {

        } -Pending
        It 'The Computername parameter should be named' {

        } -pending
    } #context
    Context Execution {

        It 'Should fail on a bad event log name' {

        } -Pending
        It 'Should call Start-ThreadJob' {

        }
        It 'Should call Write-Progress' {

        } -Pending
    }


    Context 'Format and Type' {
        BeforeAll {
            $fmt = Get-FormatData -TypeName WinEventReport
            $td = Get-TypeData wineventreport
        }
        It 'Should write a custom object to the pipeline with a typename of WinEventReport' {

        } -pending
        It 'The WinEventReport object should have a Date alias' {
            $td.members.ContainsKey("Date")
        }
        It 'Should have a table view called Security' {
            $fmt.FormatViewDefinition.Where({ $_.name -eq 'Security' }).control.GetType().name | Should -Be 'TableControl'
        }
        It 'Should have a table view called percentage' {
            $fmt.FormatViewDefinition.Where({ $_.name -eq 'Percentage' }).control.GetType().name | Should -Be 'TableControl'
        }

    } #context

    Context Other {
        It 'Should have comment based help with an example.' {
            $help.synopsis | Should -Not -Be Null
            $help.examples.example.count | Should -BeGreaterThan 2
        }
    }

} #describe