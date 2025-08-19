<#
.SYNOPSIS
    A demo script for managing pizza orders.

.DESCRIPTION
    This script allows you to create, view, and remove pizza orders.
    Each order includes a base, cheese type, and toppings. 

.PARAMETER Base
    The pizza base. Valid options: Tomato, BBQ.

.PARAMETER Cheese
    The cheese option. Valid options: Cheese, Light Cheese.

.PARAMETER Toppings
    One or more toppings. Valid options: Pepperoni, Ham, Onion, Sausage, Peppers.

.PARAMETER ShowOrder
    Displays a specific order by order number.

.PARAMETER RemoveOrder
    Removes a specific order by order number.

.PARAMETER All
    Lists all current orders, sorted by order number.

.PARAMETER NextOrder
    Displays the next available (lowest number) order.

.EXAMPLE
    New-Order -Base Tomato -Cheese Cheese -Toppings Ham, Onion
    Creates a new pizza order with tomato base, regular cheese, ham, and onion.

.EXAMPLE
    Manage-Order -ShowOrder 2
    Displays order #2.

.EXAMPLE
    Manage-Order -RemoveOrder 3
    Removes order #3.

.EXAMPLE
    Manage-Order -All
    Displays all active orders.

.NOTES
    Author: Christian Ito-Taylor
    Version: 1.0
    Date:   2025-08-18
#>

## Initialize the array for the orders list
$Pizza = @{}

function Order-Pizza {
    [CmdletBinding()]
    ## Give parameter set names so that you can't combine certian options
    ## Also verifying only my set options can be set. Helps tab-finish as well.
    param (
        [Parameter(Mandatory, ParameterSetName = 'Premade')]
        #        [ValidateSet('Classic', 'Outback', IgnoreCase=$true)]      # Removing these so I can include more user input (not sure which way would be best).
        [string]$Premade,

        [Parameter(Mandatory, ParameterSetName = 'Custom')]
        #        [ValidateSet('Tomato', 'BBQ', IgnoreCase=$true)]
        [string]$Base,

        [Parameter(Mandatory, ParameterSetName = 'Custom')]
        #        [ValidateSet('Cheese', 'Light Cheese', IgnoreCase=$true)]
        [string]$Cheese,

        [Parameter(ParameterSetName = 'Custom')]
        #        [ValidateSet('Pepperoni', 'Ham', 'Onion', 'Sausage', 'Peppers', IgnoreCase=$true)]
        [string[]]$Toppings
    )

    ## Shows what the user inputs
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
    # ======

    # === Bases ===
    ## Normalize inputs
    $Base = $Base.Trim()
    $Base = (Get-Culture).TextInfo.ToTitleCase($Base.ToLower())

    ## Validate options
    #### *** Could get more specific with bbq, barbecue, BBQ
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

    # === Toppings ===
    ## Normalize inputs
    $Toppings = 
    $Toppings | 
    Where-Object { $_ -ne $null -and $_.Trim() -ne '' } | 
    ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_.Trim().ToLower()) }

    ## Remove duplicates
    $Toppings = $Toppings | Select-Object -Unique

    ## Validate options
    $validToppings = @('Pepperoni', 'Ham', 'Onion', 'Sausage', 'Peppers')
    $invalid = $Toppings | Where-Object { $_ -notin $validToppings }
    if ($invalid) {
        throw "Invalid toppings: $($invalid -join ', '). Valid options: $($validToppings -join ', ')"
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
    # ======

    ## Shows what was actually bound to params
    Write-Verbose "Bound params: $($PSBoundParameters.Keys -join ', ')"
    Write-Verbose "Current orders: $($Pizza.Count)"

    $Pizza[$OrderNumber] = [PSCustomObject]@{
        OrderNumber = $OrderNumber
        Base        = $Base
        Cheese      = $Cheese
        Toppings    = $Toppings
    }

    Write-Output "Your order is placed.`n"
    $Pizza[$OrderNumber]
    ## Show objects stored
    Write-Verbose ("New order object: " + ($Pizza[$OrderNumber] | ConvertTo-Json -Compress))
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
        [switch]$ShowAll
    )

    ## Shows what the user input
    Write-Verbose "ParamSet: $($PSCmdlet.ParameterSetName)"
    ## Shows what was actually bound to params
    Write-Verbose "Bound params: $($PSBoundParameters.Keys -join ', ')"

    # === Show ===
    if ($PSCmdlet.ParameterSetName -eq 'Get') {
        ## Show specified order number
        if ($PSBoundParameters.ContainsKey('ShowOrder')) {
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
        if ($PSBoundParameters.ContainsKey('NextOrder')) {

            if (-not $Pizza -or $Pizza.Count -eq 0) { 
                Write-Error "No orders yet."
                return
            }
            
            ## Get lowest order #
            $next = [int](($Pizza.Keys | Measure-Object -Minimum).Minimum)
            
            if ($Pizza.ContainsKey($Next)) {
                $Pizza[$Next]
                return
            }
            else {
                Write-Error "No orders found."
            }
        }
    }
    # ======

    # === Delete ===
    ## Remove specified order
    if ($PSBoundParameters.ContainsKey('RemoveOrder')) {
        if ($Pizza.ContainsKey($RemoveOrder)) {
            [void]$Pizza.Remove([int]$RemoveOrder)
        }
        else {
            Write-Verbose "Lookup requested: Order #$ShowOrder"
            Write-Error "Order #$RemoveOrder not found."
        }
        return
    }
    # ======

    # === Show All ===
    ## Show all orders
    if ($ShowAll) {
        if ($Pizza.Count -gt 0) {
            $Pizza.Values | Sort-Object OrderNumber | Format-Table -AutoSize
        }
        return
    }
    else {
        Write-Error "No orders found."
    }
    # ======

    ## Show what was actually bound to params
    Write-Verbose "Bound params: $($PSBoundParameters.Keys -join ', ')"
}

<#  Test Runs

Order-Pizza -Premade Classic
Order-Pizza -Premade Outback -Cheese Cheese # Customizing premade should FAIL
Order-Pizza -Base bbq -Cheese 'Light Cheese' -Toppings Ham, Pepperoni, Onion -verbose
Order-Pizza -Base Tomato -Cheese 'Light Cheese' -Toppings Ham, Pep, Onion #Should FAIL - misspelled
Order-Pizza -Base Tomato -Cheese 'Light Cheese' -Toppings Ham, Onion, Onion # Double topping should be OK

Manage-Order -ShowAll -verbose
Manage-Order -ShowOrder 4 -verbose
Manage-Order -RemoveOrder 5000  # Should FAIL - not exist
Manage-Order -NextOrder
Manage-Order -ShowOrder 4 -All  # Should FAIL, incompat params
Manage-Order -RemoveOrder 1
Manage-Order -RemoveOrder 4
#>