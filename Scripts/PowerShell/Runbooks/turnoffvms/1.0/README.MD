# Runbook: Update Management - Turn Off VMs

## Details

- Runbook type: PowerShell
- Created by: Tor Ivar Asbølmo
- Status: Work in progress

## Intended usage

This script is intended to be run as a part of Update Management Pre/Post scripts.

## Requirements

It requires:

- A valid RunAsAccount or Managed Identity.
- the module 'ThreadJobs' from the PowerShell Gallery.
- Az-modules
  - Az.Accounts
  - Az.Automation
  - Az.Resources
  - Az.Compute
- the usage of the [Turn On VMs](../../turnonvms/1.0/) script as a pre-deployment script.

### Resource Permissions

The RunAsAccount or Managed Identity needs the following permissions on your subscription scope:

- Virtual Machine Contributor or custom role with permission for read/start/stop/deallocate Virtual Machine.
- Reader.

The RunAsAccount or Managed Identity needs the following permissions on your automation account:

- Contributor.

## Description

This script will ensure all Azure VMs in the Update Deployment started by [Turn On VMs](../../turnonvms/1.0/) script, are turned off after they recieve updates.

This script reads the name of machines that were started by Update Management via the [Turn On VMs](../../turnonvms/1.0/) script.
