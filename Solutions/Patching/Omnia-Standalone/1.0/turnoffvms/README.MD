# Update Management - Turn Off VMs

## Intended usage

This script is intended to be run as a part of Update Management Pre/Post scripts.

## Requirements

It requires:

- A valid RunAsAccount.
- the module 'ThreadJobs' from the PowerShell Gallery.
- Az-modules
  - Az.Accounts
  - Az.Automation
  - Az.Resources
  - Az.Compute
- the usage of the [Turn On VMs](../turnonvms/) script as a pre-deployment script.

## Description

This script will ensure all Azure VMs in the Update Deployment started by [Turn On VMs](../turnonvms/) script, are turned off after they recieve updates.

This script reads the name of machines that were started by Update Management via the [Turn On VMs](../turnonvms/) script.
