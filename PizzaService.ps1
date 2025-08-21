<#
.SYNOPSIS
    Pizza Order Management

.DESCRIPTION
    This script simulates a simple pizza ordering system.
    You can create new orders, view details, update existing orders,
    move orders through their status stages, or remove them from the queue.

.PARAMETER Base
    The pizza base for custom orders.
    Valid options: Tomato, BBQ.

.PARAMETER Cheese
    The cheese option for custom orders.
    Valid options: Cheese, Light Cheese.

.PARAMETER Toppings
    One or more toppings for custom orders.
    Valid options: Pepperoni, Ham, Onion, Sausage, Peppers.

.PARAMETER Premade
    Creates a pre-set pizza.
    Valid options: Classic, Outback, HamNCheese.

.PARAMETER Customize
    Adjusts premade pizzas.
    Use Add<Name> or No<Name>, e.g. AddHam, NoOnion.

.PARAMETER ShowOrder
    Displays a specific order by order number.

.PARAMETER ShowAll
    Displays all current orders in the queue.

.PARAMETER NextOrder
    Displays the next available (lowest order number) order.

.PARAMETER RemoveOrder
    Removes a specific order by order number.

.PARAMETER ProgressOrder
    Advances an order through the workflow:
    Preparing → OutForDelivery → Delivered.

.PARAMETER ChangeBase
    Updates the base for an existing order. Used with OrderNumber.

.PARAMETER ChangeCheese
    Updates the cheese for an existing order. Used with OrderNumber.

.PARAMETER ChangeToppings
    Updates the toppings for an existing order. Used with OrderNumber.

.PARAMETER OrderNumber
    The order ID to apply updates to. Used to make Changes.

.EXAMPLE
    Order-Pizza -Base Tomato -Cheese Cheese -Toppings Ham, Onion
    Creates a custom pizza with tomato base, cheese, ham, and onion.

.EXAMPLE
    Order-Pizza -Premade Classic
    Creates a premade "Classic" pizza.

.EXAMPLE
    Manage-Order -ShowOrder 2
    Displays order #2.

.EXAMPLE
    Manage-Order -ShowAll
    Displays all active orders.

.EXAMPLE
    Manage-Order -ProgressOrder 3
    Advances order #3 to the next stage.

.EXAMPLE
    Manage-Order -OrderNumber 2 -ChangeCheese "Light Cheese"
    Updates the cheese option for order #2.

.NOTES
    Author: Christian Ito-Taylor
    Version: 1.0
    Date:   2025-08-21
#>

# Data store
$Pizza = @{}

# === Helper Functions === #
function Show-Order {
    [CmdletBinding()]
    param(
        [int]$ShowOrder,
        [switch]$ShowAll,
        [switch]$NextOrder
    )

    ## Show specified order number
    if ($ShowOrder) {
        if ($Pizza.ContainsKey($ShowOrder)) {
            $Pizza[$ShowOrder]
            return
        }
        else {
            Write-Verbose "Lookup requested: Order #$ShowOrder"
            Write-Error "Order #$ShowOrder not found."
        }
    } 
    ## Show next order (lowest number)
    if ($NextOrder) {
        if (-not $Pizza -or $Pizza.Count -eq 0) { 
            Write-Error "No orders yet."
            return
        }
        ## Get lowest order # to show what to prep next
        $Next = [int](($Pizza.Keys | Measure-Object -Minimum).Minimum)
            
        if ($Pizza.ContainsKey($Next)) {
            $Pizza[$Next]
            return
        }
        else {
            Write-Error "No orders found."
        }
    }
    ## Show all orders
    elseif ($ShowAll) {
        if ($Pizza.Count -gt 0) {
            $Pizza.Values | Sort-Object OrderNumber | Format-Table -AutoSize
        }
        return
    }
    else {
        Write-Error "No orders found."
    }
}
function Move-Status {
    [CmdletBinding()]
    param(
        [int]$Order
    )
    ## Move status to next type: Pending → Preparing → OutForDelivery → Delivered
    switch ($Pizza[$ProgressOrder].OrderStatus) {
        'Preparing' { $Pizza[$ProgressOrder].OrderStatus = 'OutForDelivery' }
        'OutForDelivery' { $Pizza[$ProgressOrder].OrderStatus = 'Delivered' }
        'Delivered' { Write-Output "Order #$ProgressOrder already delivered." }
        default { $Pizza[$ProgressOrder].OrderStatus = 'Preparing' }
    }
    $Pizza[$ProgressOrder]
}
function Remove-Order {
    [CmdletBinding()]
    param([int]$Order)

    ## Remove specified order from queue
    if ($Pizza.ContainsKey([int]$RemoveOrder)) {
        [void]$Pizza.Remove([int]$RemoveOrder)
        "Order #$RemoveOrder has been removed from queue."
    }
    else {
        Write-Error "Order #$RemoveOrder not found."
    }
}
# === === #

# === Main Functions === #
function Order-Pizza {
    [CmdletBinding()]
    ## Give parameter set names so that you can't combine certian options
    ## Utilizing ValidateSet to verify only my set options will be accepted. Helps tab-finish as well, making it more user-friendly.
    param (
        [Parameter(Mandatory, ParameterSetName = 'Premade')]
        [ValidateSet('Classic', 'Outback', 'HamNCheese', IgnoreCase = $true)]
        [string]$Premade,

        [Parameter(ParameterSetName = 'Premade')]
        [string[]]$Customize,

        [Parameter(Mandatory, ParameterSetName = 'Custom')]
        [ValidateSet('Tomato', 'BBQ', IgnoreCase = $true)]
        [string]$Base,

        [Parameter(Mandatory, ParameterSetName = 'Custom')]
        [ValidateSet('Cheese', 'Light Cheese', IgnoreCase = $true)]
        [string]$Cheese,

        [Parameter(ParameterSetName = 'Custom')]
        [ValidateSet('Pepperoni', 'Ham', 'Onion', 'Sausage', 'Peppers', IgnoreCase = $true)]
        [string[]]$Toppings
    )

    ## Shows what the user input
    Write-Verbose "ParamSet: $($PSCmdlet.ParameterSetName)"

    # === Premade Za ===
    ## Creates the pre-made pizzas
    if ($Premade -eq "Classic") {
        $Base = "Tomato"
        $Cheese = "Cheese"
        $Toppings = @("Pepperoni", "Sausage", "Peppers")
    }
    elseif ($Premade -eq "Outback") {
        $Base = "BBQ"
        $Cheese = "Cheese"
        $Toppings = @("Sausage", "Onion", "Peppers")
    }
    elseif ($Premade -eq "HamNCheese") {
        $Base = "Tomato"
        $Cheese = "Cheese"
        $Toppings = @("Ham", "Onion")
    }
    
    ## Customize premade pizza
    if ($PSCmdlet.ParameterSetName -eq 'Premade' -and $Customize) {
        $mods = $Customize -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        foreach ($m in $mods) {
            # Regex cleaning
            if ($m -match '^(?<Action>Add|No)(?<Name>.+)$') {
                $name = $Matches['Name']

                if ($Matches['Action'] -eq 'Add') {
                    if ($name -notin $Toppings) { $Toppings += $name } # Add Topping
                }
                else {
                    $Toppings = $Toppings | Where-Object { $_ -ne $name } # Remove Topping
                }
            }
            else {
                throw "Invalid customization '$m'. Use Add<Name> or No<Name> (e.g., AddOnion, NoPeppers)."
            }
        }
        ## No duplicates!
        $Toppings = $Toppings | Select-Object -Unique
    }
    # ======

    # === Bases ===
    ## Normalize inputs
    $Base = $Base.Trim()
    $Base = (Get-Culture).TextInfo.ToTitleCase($Base.ToLower())

    ## Validate options
    $validBases = @('Tomato', 'BBQ')
    if ($Base -notin $validBases) {
        throw "Invalid base: '$Base'. Valid options are: $($validBases -join ', ')"
    }
    # ======

    # === Cheeses ===
    ## Normalize inputs
    $Cheese = $Cheese.Trim()
    $Cheese = (Get-Culture).TextInfo.ToTitleCase($Cheese.ToLower())

    ## Validate options
    $validCheeses = @('Cheese', 'Light Cheese')
    if ($Cheese -notin $validCheeses) {
        throw "Invalid cheese: '$Cheese'. Valid options are: $($validCheeses -join ', ')"
    }
    # ======

    # === Orders ===
    ## Assign an order number to each pizza
    if ($Pizza.Count -eq 0) {
        [int]$OrderNumber = 1
    }
    else {
        [int]$OrderNumber = ($Pizza.Keys | Measure-Object -Maximum).Maximum + 1
    }
    ## Set initial order status
    $OrderStatus = "Preparing"
    # ======

    ## Shows what was actually bound to params
    Write-Verbose "Bound params: $($PSBoundParameters.Keys -join ', ')"
    Write-Verbose "Current orders: $($Pizza.Count)"

    $Pizza[$OrderNumber] = [PSCustomObject]@{
        OrderNumber = $OrderNumber
        OrderStatus = $OrderStatus
        Base        = $Base
        Cheese      = $Cheese
        Toppings    = $Toppings
    }

    Write-Output "Your order is placed.`n"
    $Pizza[$OrderNumber]
    Write-Verbose ("New order object: " + ($Pizza[$OrderNumber] | ConvertTo-Json -Compress)) ## Show objects stored
}

function Manage-Order {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName = 'Get')]
        [int]$ShowOrder,

        [Parameter(ParameterSetName = 'Get')]
        [switch]$NextOrder,

        [Parameter(ParameterSetName = 'Delete')]
        [int]$RemoveOrder,

        [Parameter(ParameterSetName = 'All')]
        [switch]$ShowAll,

        [Parameter(ParameterSetName = 'Progress')]
        [int]$ProgressOrder,

        [Parameter(ParameterSetName = 'Update')]
        [ValidateSet('Pepperoni', 'Ham', 'Onion', 'Sausage', 'Peppers')]
        [string[]]$ChangeToppings,

        [Parameter(ParameterSetName = 'Update')]
        [ValidateSet('Tomato', 'BBQ')]
        [string]$ChangeBase,

        [Parameter(ParameterSetName = 'Update')]
        [ValidateSet('Cheese', 'Light Cheese')]
        [string]$ChangeCheese,

        [Parameter(ParameterSetName = 'Update')]
        [int]$OrderNumber
    )

    Write-Verbose "ParamSet: $($PSCmdlet.ParameterSetName)" ## Shows what the user input
    Write-Verbose "Bound params: $($PSBoundParameters.Keys -join ', ')" ## Shows what was actually bound to params

    ## Calling the helper functions
    switch ($PSCmdlet.ParameterSetName) {
        'Progress' { Move-Status -Order $ProgressOrder }
        'Get' { Show-Order -ShowOrder $ShowOrder -NextOrder:$NextOrder }
        'All' { Show-Order -ShowAll:$ShowAll }
        'Delete' { Remove-Order -Order $RemoveOrder }
        'Update' {
            if ($ChangeBase) { $Pizza[$OrderNumber].Base = $ChangeBase }
            if ($ChangeCheese) { $Pizza[$OrderNumber].Cheese = $ChangeCheese }
            if ($ChangeToppings) { $Pizza[$OrderNumber].Toppings = $ChangeToppings }
            $Pizza[$OrderNumber]
        }
    }
}
# === === #
