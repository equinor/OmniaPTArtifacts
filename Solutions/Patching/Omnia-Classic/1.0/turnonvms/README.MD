# Update Management - Turn On VMs

## Intended usage

This script is intended to be run as a part of Update Management Pre/Post scripts.

## Requirements

It requires:

- A valid RunAsAccount.
- The module 'ThreadJobs' from the PowerShell Gallery.
- Az-modules
  - Az.Accounts
  - Az.Automation
  - Az.Resources
  - Az.Compute

## Description

This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
This script works with the [Turn Off VMs](../turnoffvms/) script. It will store the names of machines that were started in an Automation variable so only those machines are turned back off when the deployment is finished.
