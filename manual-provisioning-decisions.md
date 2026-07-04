# Manual Provisioning Decisions - KijaniKiosk API Server

| Decision          | Value I chose | Reason |
|-------------------|---------------|--------|
| Cloud provider    |   AWS            | Existing hosting platform with the required networking and instance tooling already in place. |
| Region            |   us-east-1    | Chosen for low latency, broad service availability, and alignment with the rest of the environment. |
| Operating system  |   Ubuntu, 24.04, | Long-term support release with strong package support and predictable security updates. |
| Instance type     |   t3.micro       | Small, low-cost instance appropriate for a lightweight server and early-stage provisioning. |
| VPC               |   vpc-080d53caa1a4a3c91  | Uses the existing isolated network boundary for the environment. |
| Subnet            |   subnet-0a36534d5f1e3ea51 | Places the instance in the correct reachable subnet for the application. |
| Security group    |  sg-0adaf0cf80c5f6442             | Applies the required ingress and egress rules while keeping access tightly controlled. |
| SSH key pair      |   main-key            | Provides secure administrative access using the approved key pair. |
| Root volume size  |    8GiB           | Sufficient for the base OS and application footprint while keeping storage minimal. |
| Public IP?        | 98.93.124.227              | Needed for direct remote access and initial provisioning validation. |
| Tags / labels     |   Amina           | Owner tag for resource ownership and cost allocation. |