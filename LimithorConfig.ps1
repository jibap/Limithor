# LimithorConfig.ps1 - GUI (admin) pour éditer C:\Program Files\Limithor\config.json
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$cfgPath = "C:\Program Files\Limithor\config.json"
function Load-Config { if (Test-Path $cfgPath) { try { Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { @{users=@{}} } } else { @{users=@{}} } }
function Save-Config($cfg) { $cfg | ConvertTo-Json -Depth 8 | Set-Content $cfgPath -Encoding UTF8 }
$cfg = Load-Config; if (-not $cfg.users) { $cfg = @{users=@{}} }

$form = New-Object Windows.Forms.Form; $form.Text="Limithor - Configuration"; $form.Size=New-Object Drawing.Size(520,420); $form.StartPosition="CenterScreen"
$lblUser=New-Object Windows.Forms.Label; $lblUser.Text="Utilisateur"; $lblUser.Location='20,20'; $lblUser.AutoSize=$true
$txtUser=New-Object Windows.Forms.TextBox; $txtUser.Location='200,18'; $txtUser.Width=250
$lblDur =New-Object Windows.Forms.Label; $lblDur.Text="Durée (minutes)"; $lblDur.Location='20,60'; $lblDur.AutoSize=$true
$numDur=New-Object Windows.Forms.NumericUpDown; $numDur.Location='200,58'; $numDur.Width=100; $numDur.Minimum=1; $numDur.Maximum=100000; $numDur.Value=2
$lblCycle=New-Object Windows.Forms.Label; $lblCycle.Text="Cycle"; $lblCycle.Location='20,100'; $lblCycle.AutoSize=$true
$cbCycle=New-Object Windows.Forms.ComboBox; $cbCycle.Location='200,98'; $cbCycle.Width=150; $cbCycle.DropDownStyle='DropDownList'; [void]$cbCycle.Items.AddRange(@('daily','weekly','monthly')); $cbCycle.SelectedIndex=0
$lblAct =New-Object Windows.Forms.Label; $lblAct.Text="Action"; $lblAct.Location='20,140'; $lblAct.AutoSize=$true
$cbAct =New-Object Windows.Forms.ComboBox; $cbAct.Location='200,138'; $cbAct.Width=150; $cbAct.DropDownStyle='DropDownList'; [void]$cbAct.Items.AddRange(@('logoff','lock')); $cbAct.SelectedIndex=0
$btnAdd=New-Object Windows.Forms.Button; $btnAdd.Text="Ajouter / Mettre à jour"; $btnAdd.Location='20,180'
$btnDel=New-Object Windows.Forms.Button; $btnDel.Text="Supprimer"; $btnDel.Location='200,180'

$lv = New-Object Windows.Forms.ListView; $lv.Location='20,220'; $lv.Size=New-Object Drawing.Size(460,140); $lv.View='Details'; $lv.FullRowSelect=$true
[void]$lv.Columns.Add("Utilisateur", 120); [void]$lv.Columns.Add("Durée", 80); [void]$lv.Columns.Add("Cycle", 120); [void]$lv.Columns.Add("Action", 120)
$form.Controls.AddRange(@($lblUser,$txtUser,$lblDur,$numDur,$lblCycle,$cbCycle,$lblAct,$cbAct,$btnAdd,$btnDel,$lv))

function Refresh-List {
  $lv.Items.Clear()
  foreach ($k in $cfg.users.PSObject.Properties.Name) {
    $o = $cfg.users.$k; $it = New-Object Windows.Forms.ListViewItem($k)
    [void]$it.SubItems.Add([string]$o.duration); [void]$it.SubItems.Add([string]$o.cycle); [void]$it.SubItems.Add([string]$o.action)
    [void]$lv.Items.Add($it)
  }
}
Refresh-List

$btnAdd.Add_Click({
  $user = $txtUser.Text.Trim().ToLower(); if (-not $user) { [Windows.Forms.MessageBox]::Show("Renseigne un nom d'utilisateur"); return }
  $cfg.users.$user = @{ duration=[int]$numDur.Value; cycle=$cbCycle.SelectedItem; action=$cbAct.SelectedItem }
  try { Save-Config $cfg; Refresh-List; [Windows.Forms.MessageBox]::Show("Enregistré.") } catch { [Windows.Forms.MessageBox]::Show("Erreur: $($_.Exception.Message)") }
})

$btnDel.Add_Click({
  if ($lv.SelectedItems.Count -eq 0) { [Windows.Forms.MessageBox]::Show("Sélectionne un utilisateur à supprimer."); return }
  $user = $lv.SelectedItems[0].Text
  if ([Windows.Forms.MessageBox]::Show("Supprimer l'utilisateur '"+$user+"' ?","Confirmation",[Windows.Forms.MessageBoxButtons]::YesNo) -eq 'Yes') {
    $cfg.users.PSObject.Properties.Remove($user)
    try { Save-Config $cfg; Refresh-List; [Windows.Forms.MessageBox]::Show("Supprimé.") } catch { [Windows.Forms.MessageBox]::Show("Erreur: $($_.Exception.Message)") }
  }
})

[void]$form.ShowDialog()
