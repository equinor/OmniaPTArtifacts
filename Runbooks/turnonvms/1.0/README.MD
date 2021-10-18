# Update Management - Turn On VMs

## Details

- Runbook type: PowerShell
- Created by: Tor Ivar Asbølmo
- Status: Ready for testing

## Intended usage

This script is intended to be run as a part of Update Management Pre/Post scripts.

## Requirements

It requires:

- A valid RunAsAccount or Managed Identity.
- The module 'ThreadJobs' from the PowerShell Gallery.
- Az-modules
  - Az.Accounts
  - Az.Automation
  - Az.Resources
  - Az.Compute
- the usage of the [Turn Off VMs](../../turnonvms/1.0/) script as a post-deployment script.

### Resource Permissions

The RunAsAccount or Managed Identity needs the following permissions on your subscription scope:

- Virtual Machine Contributor or custom role with permission for read/start/stop/deallocate Virtual Machine.
- Reader.

The RunAsAccount or Managed Identity needs the following permissions on your automation account:

- Contributor.

## Description

This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
This script works with the [Turn Off VMs](../../turnoffvms/) script. It will store the names of machines that were started in an Automation variable so only those machines are turned back off when the deployment is finished.
