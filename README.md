Lead DevOps Assignment

Deploying a React Application using EKS cluster build with terraform, AWS and Docker.
Step to Complete the project

AWS account
AWS CLI Configuration
Terraform Installation on Locally/CI-CD Server(If it is run from Pipeline)
Docker Image creation and Pushed to Docker hub or any Local registry(here i use  docker hub) using Jenkins pipeline.
Security Group Inbound rule update as per kubernetes SVC nodeport.


Configuring AWS CLI:

In your browser, download the macOS pkg file: https://awscli.amazonaws.com/AWSCLIV2.pkg
Run your downloaded file and follow the on-screen instructions. You can choose to install the AWS CLI in the following ways:
For all users on the computer (requires sudo)
You can install to any folder, or choose the recommended default folder of /usr/local/aws-cli.
The installer automatically creates a symlink at /usr/local/bin/aws that links to the main program in the installation folder you chose.
Finally, configure the AWS CLI for Ubuntu or MAC.

Install terraform and write the terraform code or Clone the code from Github repo.
App Repository: https://github.com/MdRasel0/react-app-eno 
Terraform repository: https://github.com/MdRasel0/eks_cluster_tf 

Now run the code,
 
Initialize the code to download and setup all the related modules by giving the below command.

#  terrafrom init
# terrafrom plan
# terraform apply –auto-approve

AWS EKS Cluster overview:




Build The React Application using Jenkins Pipeline

By using Jenkins file we can build and push The docker images to docker hub and deploy it to EKS cluster using deployment and service manifest which are attached on github repo.

Alternatively we can build image from CLI then push it to the Dockerhub and deploy it to EKS.

# docker tag nodeenos rasel009/demo-eks-app:v1
 # docker push rasel009/demo-eks-app:v1
 # docker ps -a
If you are using mac M Series chip.
 # docker buildx build --platform linux/amd64 -t rasel009/demo-eks-app:v1 --push .
After applying the manifest The output will be:




The Final Output.





