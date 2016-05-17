# ScorchDev
Continuous Deployment for Azure Automation

Deployment Steps:

Fork this repository.
Clone the repository locally
    Suggested path is c:\git
Setup LocalDev
    Use profile/profile.ps1 as a guide

Update Globals\zzGlobal.json

Create local credentials for
    zzGlobal-SubscriptionAccessCredentialName
    zzGlobal-RunbookWorkerAccessCredentialName
    zzGlobal-WorkspaceId
        The password should be the primary key for the log analytics workspace
        The workspace must have the automation solution deployed

Push changes to repository

change directory to C:\git\SCOrchDev\ARM\automation-sourcecontrol
run ./psDeploy.ps1

Deploy new Virtual Machine(s) to become hybrid runbook workers
Add them to the node type AzureAutomation.HybridRunbookWorker in your newly configured Azure Automation Account

Create webhook for Invoke-GitRepositorySync
    Set to run on hybrid runbook worker group
Tie webhook to deploy action of source control

Deploy code!

Bonus!
    Checkout appveyor.yml for idea on how to integrate appveyor to the solution for Continuous Integration / Continuous Deployment (CI/CD) instead of just CD

Master Branch Status: [![Build status](https://ci.appveyor.com/api/projects/status/x2ok9ch7xksiynbj/branch/master?svg=true)](https://ci.appveyor.com/project/randorfer/scorchdev/branch/master)
vNext Branch Status: [![Build status](https://ci.appveyor.com/api/projects/status/x2ok9ch7xksiynbj/branch/vNext?svg=true)](https://ci.appveyor.com/project/randorfer/scorchdev/branch/vNext)