# Set up of Session variables.
##############################################################################################
if (!(Test-Path variable:Global:SshSessions ))
{
    $global:SshSessions = New-Object System.Collections.ArrayList
}

if (!(Test-Path variable:Global:SFTPSessions ))
{
    $global:SFTPSessions = New-Object System.Collections.ArrayList
}

# Dot Sourcing of functions
##############################################################################################
# Library has to many bugs on forwarding still
#. "$PSScriptRoot\PortForward.ps1"
. "$PSScriptRoot\Trust.ps1"
. "$PSScriptRoot\Sftp.ps1"


# SSH Functions
##############################################################################################


# .ExternalHelp Posh-SSH.psm1-Help.xml
function Get-SSHSession 
{
    [CmdletBinding()]
    param( 
        [Parameter(Mandatory=$false,
                   Position=0)]
        [Alias('Index')]
        [Int32]
        $SessionId
    )

    Begin{}
    Process
    {
        if ($SessionId)
        {
            foreach($i in $SessionId)
            {
                foreach($session in $SshSessions)
                {
                    if ($session.SessionId -eq $i)
                    {
                        $session
                    }
                }
            }
        }
        else
        {
            # Can not reference SShSessions directly so as to be able
            # to remove the sessions when Remove-SSHSession is used
            $return_sessions = @()
            foreach($s in $SshSessions){$return_sessions += $s}
            $return_sessions
        }
    }
    End{}
}


# .ExternalHelp Posh-SSH.psm1-Help.xml
function Remove-SSHSession
{
    [CmdletBinding(DefaultParameterSetName='Index')]
    param(
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Index',
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Alias('Index')]
        [Int32[]]
        $SessionId,

        [Parameter(Mandatory=$false,
                   ParameterSetName = 'Session',
                   ValueFromPipeline=$true,
                   Position=0)]
        [Alias('Name')]
        [SSH.SSHSession[]]
        $SSHSession
        )

        Begin{}
        Process
        {
            if ($PSCmdlet.ParameterSetName -eq 'Index')
            {
                $sessions2remove = @()
                 foreach($i in $SessionId)
                {
                    foreach($session in $Global:SshSessions)
                    {
                        if ($session.SessionId -eq $i)
                        {
                            $sessions2remove += $session
                        }
                    }
                }

                foreach($badsession in $sessions2remove)
                {
                     Write-Verbose "Removing session $($badsession.SessionId)"
                     if ($badsession.session.IsConnected) 
                     { 
                        $badsession.session.Disconnect() 
                     }
                     $badsession.session.Dispose()
                     $global:SshSessions.Remove($badsession)
                     Write-Verbose "Session $($badsession.SessionId) Removed"
                }
            }

            if ($PSCmdlet.ParameterSetName -eq 'Session')
            {
                $sessions2remove = @()
                 foreach($i in $SSHSession)
                {
                    foreach($ssh in $Global:SshSessions)
                    {
                        if ($ssh -eq $i)
                        {
                            $sessions2remove += $ssh
                        }
                    }
                }

                foreach($badsession in $sessions2remove)
                {
                     Write-Verbose "Removing session $($badsession.SessionId)"
                     if ($badsession.session.IsConnected) 
                     { 
                        $badsession.session.Disconnect() 
                     }
                     $badsession.session.Dispose()
                     $Global:SshSessions.Remove($badsession)
                     Write-Verbose "Session $($badsession.SessionId) Removed"
                }
            }

        }
        End{}
    
}


# .ExternalHelp Posh-SSH.psm1-Help.xml
function Invoke-SSHCommand
{
    [CmdletBinding(DefaultParameterSetName='Index')]
    param(

        [Parameter(Mandatory=$true,
                   Position=1)]
        [string]$Command,
        
        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Session',
                   ValueFromPipeline=$true,
                   Position=0)]
        [Alias('Name')]
        [SSH.SSHSession[]]
        $SSHSession,

        [Parameter(Mandatory=$true,
                   ParameterSetName = 'Index',
                   Position=0)]
        [Alias('Index')]
        [int32[]]
        $SessionId = $null,

        # Ensures a connection is made by reconnecting before command.
        [Parameter(Mandatory=$false)]
        [switch]
        $EnsureConnection,

        [Parameter(Mandatory=$false,
                   Position=2)]
        [int]
        $TimeOut = 60

    )

    Begin
    {
        $ToProcess = @()
        switch($PSCmdlet.ParameterSetName)
        {
            'Session'
            {
                $ToProcess = $SSHSession
            }

            'Index'
            {
                foreach($session in $Global:SshSessions)
                {
                    if ($SessionId -contains $session.SessionId)
                    {
                        $ToProcess += $session
                    }
                }
            }
        }
    }
    Process
    {
        foreach($Connection in $ToProcess)
        {
            if ($Connection.session.isconnected)
                {
                    if ($EnsureConnection)
                    {
                        $Connection.session.connect()
                    }
                    $cmd = $Connection.session.CreateCommand($Command)
                }
                else
                {
                    $s.session.connect()
                    $cmd = $Connection.session.CreateCommand($Command)
                }

                $cmd.CommandTimeout = New-TimeSpan -Seconds $TimeOut

                # start asynchronious execution of the command.
                $Async = $cmd.BeginExecute()
                while($Async.IsCompleted)
                {
                    Write-Verbose -Message 'Waiting for command to finish execution'
                    try
                    {
                        Start-Sleep -Seconds 2
                    }
                    finally
                    {
                        $Output = $cmd.EndExecute($Async)
                    }
                }

                $Output = $cmd.EndExecute($Async)
                $ResultProps = @{}
                $ResultProps['Output'] = $Output
                $ResultProps['ExitStatus'] = $cmd.ExitStatus
                $ResultProps['Error'] = $cmd.Error
                $ResultProps['Host'] = $Connection.Host

                $ResultObj = New-Object psobject -Property $ResultProps
                $ResultObj.pstypenames.insert(0,'Renci.SshNet.SshCommand')
                $ResultObj


        }

    }
    End{}
}


# .ExternalHelp Posh-SSH.psm1-Help.xml
 function Get-PoshSSHModVersion
 {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    Param()
    
    Begin
    {
       $currentversion = ''
       $installed = Get-Module -Name 'posh-SSH' -ListAvailable
    }
    Process
    {
       $webClient = New-Object System.Net.WebClient
       Try
       {
           $current = Invoke-Expression  $webClient.DownloadString('https://raw.github.com/darkoperator/Posh-SSH/master/Posh-SSH.psd1')
           $currentversion = $current.moduleversion
       }
       Catch
       {
           Write-Warning 'Could not retrieve the current version.'
       }
       $majorver,$minorver = $currentversion.split('.')
       if ($majorver -gt $installed.Version.Major)
       {
           Write-Warning 'You are running an outdated version of the module.'
       }
       elseif ($minorver -gt $installed.Version.Minor)
       {
           Write-Warning 'You are running an outdated version of the module.'
       } 
        
       $props = @{
           InstalledVersion = $installed.Version.ToString()
           CurrentVersion   = $currentversion
       }
       New-Object -TypeName psobject -Property $props
     }
     End{}
 }


<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function New-SSHShellStream
{
    [CmdletBinding(DefaultParameterSetName="Index")]
    Param
    (
        [Parameter(Mandatory=$true,
            ParameterSetName = "Session",
            ValueFromPipeline=$true,
            Position=0)]
        [Alias("Session")]
        [SSH.SSHSession]
        $SSHSession,

        [Parameter(Mandatory=$true,
            ParameterSetName = "Index",
            ValueFromPipeline=$true,
            Position=0)]
        [Alias('Index')]
        [Int32]
        $SessionId,

        # Name of the terminal.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $TerminalName = "PoshSSHTerm",

        # The columns
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $Colums=80,

        # The rows.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $Rows=24,

        # The width.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $With= 800,

        # The height.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $Height=600,

        # Size of the buffer.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $BufferSize=1000
    )

    Begin
    {
        $ToProcess = $null
        switch($PSCmdlet.ParameterSetName)
        {
            'Session'
            {
                $ToProcess = $SSHSession
            }

            'Index'
            {
                $sess = Get-SSHSession -Index $SessionId
                if ($sess)
                {
                    $ToProcess = $sess
                }
                else
                {
                    Write-Error -Message "Session specified with Index $($SessionId) was not found"
                    return
                }
            }
        }
    }
    Process
    {
        $ToProcess.Session.CreateShellStream($TerminalName, $Colums, $Rows, $With, $Height, $BufferSize)
    }
    End
    {
    }
}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Invoke-SSHStreamExpectAction
{
    [CmdletBinding(DefaultParameterSetName='String')]
    Param
    (
        # SSH Shell Stream. 
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromPipeline=$true,
                   Position=0)]
        [Renci.SshNet.ShellStream]
        $ShellStream,

        # Initial command that will generate the output to be evaluated by the expect pattern.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [string]
        $Command,

        # String on what to trigger the action on.
        [Parameter(Mandatory=$true,
                   ParameterSetName='String',
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [string]
        $ExpectString,

        # Regular expression on what to trigger the action on.
        [Parameter(Mandatory=$true,
                   ParameterSetName='Regex',
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [regex]
        $ExpectRegex,

        # Command to execute once an expression is matched.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=3)]
        [string]
        $Action,

        # Number of seconds to wait for a match.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=4)]
        [int]
        $TimeOut = 10
    )

    Begin
    {
    }
    Process
    {
        Write-Verbose -Message "Executing command $($Command)."
        $ShellStream.WriteLine($Command)
        Write-Verbose -Message "Waiting for match."
        switch ($PSCmdlet.ParameterSetName)
        {
            'string' {$found = $ShellStream.Expect($ExpectString, (New-TimeSpan -Seconds $TimeOut))}
            'Regex'  {$found = $ShellStream.Expect($ExpectRegex, (New-TimeSpan -Seconds $TimeOut))}
        }
        
        if ($found -ne $null)
        {
            Write-Verbose -Message "Executing action: $($Action)."
            $ShellStream.WriteLine($Action)
            Write-Verbose -Message 'Action has been executed.'
        }
        else
        {
            Write-Warning -Message 'Expect timeout without achiving a match.'
        }
    }
    End
    {
    }
}

<#
.Synopsis
   Executes an action stored in a secure string when an output is matched. 
.DESCRIPTION
   Executes an action stored in a secure string when an output is matched. By
   the expect action being in a secure string this function is best used when a
   password must be provided to a promp protecting it in memory. Examples 
   uses would be for use in su or sudo commands.
.EXAMPLE

    Invoke-SSHStreamExpectSecureAction -ShellStream $stream -Command 'su -' -ExpectString 'Passord:' -SecureAction (read-host -AsSecureString) -Verbose
    ***********
    VERBOSE: Executing command su -.
    VERBOSE: Waiting for match.
    VERBOSE: Executing action.
    VERBOSE: Action has been executed.
    PS C:\> $stream.Read()

    Last login: Sat Mar 14 18:18:52 EDT 2015 on pts/0
    Last failed login: Sun Mar 15 08:52:07 EDT 2015 on pts/0
    There were 2 failed login attempts since the last successful login.
    [root@localhost ~]#

.EXAMPLE
     $sudoPassPropmp = [regex]':\s$'
    PS C:\> Invoke-SSHStreamExpectSecureAction -ShellStream $stream -Command 'sudo ifconfig' -ExpectRege
    x $sudoPassPropmp -SecureAction (read-host -AsSecureString) -Verbose
    ***********
    VERBOSE: Executing command sudo ifconfig.
    VERBOSE: Waiting for match.
    VERBOSE: Matching by RegEx.
    VERBOSE: Executing action.
    VERBOSE: Action has been executed.
    PS C:\> $stream.Read()

    [sudo] password for admin:
    ens192: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
            inet 192.168.1.180  netmask 255.255.240.0  broadcast 192.168.15.255
            inet6 fe80::20c:29ff:feeb:34a0  prefixlen 64  scopeid 0x20<link>
            ether 00:0c:29:eb:34:a0  txqueuelen 1000  (Ethernet)
            RX packets 300644  bytes 175076049 (166.9 MiB)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 139657  bytes 56363667 (53.7 MiB)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
            inet 127.0.0.1  netmask 255.0.0.0
            inet6 ::1  prefixlen 128  scopeid 0x10<host>
            loop  txqueuelen 0  (Local Loopback)
            RX packets 0  bytes 0 (0.0 B)
            RX errors 0  dropped 0  overruns 0  frame 0
            TX packets 0  bytes 0 (0.0 B)
            TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

    [admin@localhost ~]$
#>
function Invoke-SSHStreamExpectSecureAction
{
    [CmdletBinding(DefaultParameterSetName='String')]
    [OutputType([int])]
    Param
    (
        # SSH Shell Stream. 
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ValueFromPipeline=$true,
                   Position=0)]
        [Renci.SshNet.ShellStream]
        $ShellStream,

        # Initial command that will generate the output to be evaluated by the expect pattern.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [string]
        $Command,

        # String on what to trigger the action on.
        [Parameter(Mandatory=$true,
                   ParameterSetName='String',
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [string]
        $ExpectString,

        # Regular expression on what to trigger the action on.
        [Parameter(Mandatory=$true,
                   ParameterSetName='Regex',
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [regex]
        $ExpectRegex,

        # SecureString representation of action once an expression is matched.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=3)]
        [securestring]
        $SecureAction,

        # Number of seconds to wait for a match.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=4)]
        [int]
        $TimeOut = 10
    )

    Begin
    {
    }
    Process
    {
        Write-Verbose -Message "Executing command $($Command)."
        $ShellStream.WriteLine($Command)
        Write-Verbose -Message "Waiting for match."
        switch ($PSCmdlet.ParameterSetName)
        {
            'string' {
                Write-Verbose -Message 'Matching by String.'
                $found = $ShellStream.Expect($ExpectString, (New-TimeSpan -Seconds $TimeOut))
             }

            'Regex'  {
                Write-Verbose -Message 'Matching by RegEx.'
                $found = $ShellStream.Expect($ExpectRegex, (New-TimeSpan -Seconds $TimeOut))
             }
        }
        
        if ($found -ne $null)
        {
            Write-Verbose -Message "Executing action."
            $ShellStream.WriteLine([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureAction)))
            Write-Verbose -Message 'Action has been executed.'
            $SecureAction.Dispose()
            
        }
        else
        {
            Write-Warning -Message 'Expect timeout without achiving a match.'
        }
    }
    End
    {
    }
}