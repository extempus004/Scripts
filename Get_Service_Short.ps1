Get-Service *Xbox* | Select-Object $._Name, $._StartType | Export-Csv c:\temp\1.csv
