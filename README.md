# Omnia Product Team Artifacts (PUBLIC!)

**DISCLAIMER: Everything you commit to this repository is publicly available on the internet for unauthenticated and unauthorized users. Consider content audience before pushing to this repository!**

This repository is used for publicly available artifacts necessary in different parts of the Omnia solutions.

## Usage

Put public facing artifacts here. Currently there are some runbooks meant for consumption in an Azure Automation runbook.

## Structure

After some discussion, this is the current structure for the repository:

- Repository root
  - Runbooks (for Azure Automation Runbooks)
    - RunbookName
      - [Simver](https://simver.org/) 0.1/0.5/0.9/1.0/1.1/etc.
        - RunbookName.ps1
        - Readme.md

Improvements and non-breaking changes on structure will be done continuously after team discussions.

## Contribute

If you can't find a suitable path for your work, please suggest a place for it. We will handle the suggestions in a Pull Request Review.

Thank you!

### Branching

Future contributions must be done by pull request only. A branch protection rule ensures no commits directly on main branch.
Branching strategy to be used is the [Github flow](https://guides.github.com/introduction/flow/).

This means that you create a short-lived branch, make your changes there, and do a pull request to merge with main branch. The code/content will then be reviewed by Omnia Product Team, and evaluated based on company policy compliance.

Give your branch a name which identifies yourself, and which feature/functionality you are working with. These branches are supposed to live for the duration of your work, and be deleted when handled in a pull request. When you are ready for merging changes into main branch, please create a Pull Request, and assign the relevant approver. All Pull Requests must be approved by at least one approver, and this can not be yourself.

### Code formatting

We have some style recommendations for contributing code to this repository. Please see the root [vscode settings file](.vscode/settings.json) for these. There is also [recommendations](.vscode/extensions.json) for extensions in VSCode.
VSCode will interpret these files, and automatically suggest the extensions. It will also analyze code on the fly, and recommend changes based on settings file.

We recommend using Visual Studio Code for contributing to this code repository. Both because it is a nice, lightweight editor, but also because we then can use the same code style with settings.json files.
