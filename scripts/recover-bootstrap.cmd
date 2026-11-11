@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Import existing bootstrap resources after local state deletion. NEVER applies.
rem Must execute from repository clone with terraform/bootstrap/terraform.tfvars.
rem Required first: Terraform-only enablement of Cloud Resource Manager API.
set "TF=C:\terraform\terraform.exe"
cd /d "%~dp0..\terraform\bootstrap" || exit /b 1
if not exist "terraform.tfvars" (
  echo Missing terraform/bootstrap/terraform.tfvars - restore the local variables first.
  exit /b 1
)
if not exist "%TF%" (
  echo Terraform executable missing: %TF%
  exit /b 1
)
if not exist "%~dp0recovery-deployer-writer.tf.template" (
  echo Missing recovery-deployer-writer.tf.template
  exit /b 1
)
copy /Y "%~dp0recovery-deployer-writer.tf.template" "_recovery_writer.tf" >nul
if errorlevel 1 exit /b 1
echo Importing existing Terraform resources. This updates local STATE ONLY.
echo The old deployer writer will be imported then planned for revocation.
call :IMPORT "google_artifact_registry_repository.api" "projects/commitask/locations/europe-west1/repositories/meridian-poc"
if errorlevel 1 exit /b 1
call :IMPORT "google_iam_workload_identity_pool.github" "projects/commitask/locations/global/workloadIdentityPools/meridian-github"
if errorlevel 1 exit /b 1
call :IMPORT "google_iam_workload_identity_pool_provider.github_main_plan" "projects/commitask/locations/global/workloadIdentityPools/meridian-github/providers/github-plan"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""deployer""]" "projects/commitask/serviceAccounts/meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""api""]" "projects/commitask/serviceAccounts/meridian-poc-api@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""migration""]" "projects/commitask/serviceAccounts/meridian-poc-migration@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""dev1""]" "projects/commitask/serviceAccounts/meridian-poc-dev1@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""dev2""]" "projects/commitask/serviceAccounts/meridian-poc-dev2@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.identity[""dev3""]" "projects/commitask/serviceAccounts/meridian-poc-dev3@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account.ci_plan" "projects/commitask/serviceAccounts/meridian-poc-plan@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_service.artifactregistry" "commitask/artifactregistry.googleapis.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_service.iam" "commitask/iam.googleapis.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_service.iamcredentials" "commitask/iamcredentials.googleapis.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_service.storage" "commitask/storage.googleapis.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_service.sts" "commitask/sts.googleapis.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_storage_bucket.terraform_state" "commitask-tfstate-924903658971"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.commit_reviewer_viewer" "commitask roles/viewer group:gcp-hr@comm-it.cloud"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/cloudsql.admin""]" "commitask roles/cloudsql.admin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/compute.networkAdmin""]" "commitask roles/compute.networkAdmin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/run.admin""]" "commitask roles/run.admin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/secretmanager.admin""]" "commitask roles/secretmanager.admin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/servicenetworking.networksAdmin""]" "commitask roles/servicenetworking.networksAdmin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.deployer[""roles/serviceusage.serviceUsageAdmin""]" "commitask roles/serviceusage.serviceUsageAdmin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.ci_plan_project_roles[""roles/viewer""]" "commitask roles/viewer serviceAccount:meridian-poc-plan@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.ci_plan_project_roles[""roles/iam.securityReviewer""]" "commitask roles/iam.securityReviewer serviceAccount:meridian-poc-plan@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.runtime_sql[""api-roles/cloudsql.client""]" "commitask roles/cloudsql.client serviceAccount:meridian-poc-api@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.runtime_sql[""api-roles/cloudsql.instanceUser""]" "commitask roles/cloudsql.instanceUser serviceAccount:meridian-poc-api@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.runtime_sql[""migration-roles/cloudsql.client""]" "commitask roles/cloudsql.client serviceAccount:meridian-poc-migration@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_project_iam_member.runtime_sql[""migration-roles/cloudsql.instanceUser""]" "commitask roles/cloudsql.instanceUser serviceAccount:meridian-poc-migration@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_storage_bucket_iam_member.deployer_state" "b/commitask-tfstate-924903658971 roles/storage.objectAdmin serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_storage_bucket_iam_member.ci_plan_state" "b/commitask-tfstate-924903658971 roles/storage.objectViewer serviceAccount:meridian-poc-plan@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account_iam_member.deployer_act_as_api" "projects/commitask/serviceAccounts/meridian-poc-api@commitask.iam.gserviceaccount.com roles/iam.serviceAccountUser serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account_iam_member.deployer_act_as_migration" "projects/commitask/serviceAccounts/meridian-poc-migration@commitask.iam.gserviceaccount.com roles/iam.serviceAccountUser serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account_iam_member.terraform_operator_token_creator[0]" "projects/commitask/serviceAccounts/meridian-poc-deployer@commitask.iam.gserviceaccount.com roles/iam.serviceAccountTokenCreator user:karu.lior@gmail.com"
if errorlevel 1 exit /b 1
call :IMPORT "google_service_account_iam_member.github_main_plan" "projects/commitask/serviceAccounts/meridian-poc-plan@commitask.iam.gserviceaccount.com roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/924903658971/locations/global/workloadIdentityPools/meridian-github/attribute.repository/Comeon2022/CommitTask"
if errorlevel 1 exit /b 1
call :IMPORT "google_artifact_registry_repository_iam_member.deployer_push" "projects/commitask/locations/europe-west1/repositories/meridian-poc roles/artifactregistry.writer serviceAccount:meridian-poc-deployer@commitask.iam.gserviceaccount.com"
if errorlevel 1 exit /b 1
del "_recovery_writer.tf"
if errorlevel 1 exit /b 1
echo.
echo Imported existing resources. Check: terraform state list
echo NEXT: terraform plan -out=bootstrap-recovered.tfplan
echo Expect ONLY new builder/API additions and removal of old deployer writer.
echo DO NOT APPLY until plan is reviewed. Keep state files secure.
exit /b 0

:IMPORT
set "ADDRESS=%~1"
set "IDENTIFIER=%~2"
"%TF%" state show "%ADDRESS%" >nul 2>&1
if not errorlevel 1 (
 echo Already tracked: %ADDRESS%
 exit /b 0
)
echo Importing: %ADDRESS%
"%TF%" import -input=false "%ADDRESS%" "%IDENTIFIER%"
if errorlevel 1 (
 echo.
 echo Import FAILED: %ADDRESS%
 echo Fix the issue and rerun this script. Partial imports are persisted.
 exit /b 1
)
exit /b 0
