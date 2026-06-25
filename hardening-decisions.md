**KijaniKiosk Security Hardening Decisions Summary**

This document explains the key security decisions implemented to protect KijaniKiosk systems and data. Each decision is designed to reduce business risk, support compliance expectations, and ensure operational continuity without requiring ongoing manual intervention. The focus has been on preventing unauthorized access, limiting the impact of potential failures, and ensuring that critical monitoring and audit capabilities remain intact at all times.

First, access to shared operational data has been tightly controlled so that each system component can only perform the actions it absolutely needs. This minimizes the chance that a fault in one component could disrupt others or expose sensitive information. By enforcing clear boundaries between services, we reduce the likelihood of cascading failures or unintended data exposure.

Second, we ensured that access permissions remain consistent even during routine system maintenance activities such as log rotation. Without this safeguard, systems can silently lose access to critical files, leading to missing logs, failed transactions, or gaps in monitoring. The design guarantees that normal maintenance does not introduce hidden failures.

Third, monitoring visibility has been preserved as a first-class requirement. Security controls are often implemented in ways that unintentionally block monitoring systems, which creates blind spots. In this case, we explicitly ensured that monitoring retains read access at all times, so operational issues can be detected and addressed promptly.

Fourth, we reduced reliance on manual intervention. Any process that requires a human to “fix permissions” or restore access after routine operations introduces both risk and inconsistency. Automation ensures that the system behaves predictably and securely every time, regardless of who is operating it.

Fifth, we limited the privileges of application components to the minimum required for their function. This reduces the potential damage if one component is compromised. Instead of having broad system access, each component operates within a constrained environment, significantly lowering overall risk.

Sixth, we enforced consistent ownership and access policies for newly created files. This ensures that new data immediately complies with security expectations, rather than relying on after-the-fact corrections. It also prevents subtle failures that might only appear after system changes or restarts.

Seventh, we validated the entire model through simulation of real-world operations. Rather than assuming the design works, we tested it under the same conditions it will face in production. This approach identifies integration issues early and ensures that controls function as intended when it matters most.

Finally, we documented and verified a definitive test that proves the system continues to function securely after maintenance events. This provides a simple and reliable way to confirm that the environment remains healthy, reducing uncertainty for operations teams and leadership.

The following table summarizes the key controls, what they do, and the specific risks they mitigate:

| Control                      | What it does                                                      | Risk mitigated                                        |
| ---------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------- |
| POSIX Permissions            | Defines baseline ownership and access rights for files            | Unauthorized access or modification of sensitive data |
| Default ACLs (setfacl -d)    | Automatically applies correct access rules to newly created files | Loss of access consistency after file creation        |
| Explicit ACLs (setfacl)      | Grants precise read/write permissions to required services        | Over-permissioning or service disruption              |
| logrotate create directive   | Ensures new files are created with correct ownership and mode     | Service failure after log rotation                    |
| Service Isolation            | Restricts each service to only necessary capabilities             | Lateral movement if one service is compromised        |
| Principle of Least Privilege | Limits access rights to the minimum required                      | Excessive permissions increasing attack impact        |
| Monitoring Read Access ضمان  | Preserves monitoring visibility into system logs                  | Undetected failures or security incidents             |
| Automated Verification Test  | Confirms system access works after maintenance events             | Silent failures going unnoticed                       |
| Forced Rotation Testing      | Simulates real maintenance to validate behavior                   | Undiscovered integration issues in production         |

While these controls significantly strengthen the system, it is important to acknowledge what they do not protect against. This design does not prevent vulnerabilities within the application code itself, nor does it stop an attacker who already has legitimate credentials from misusing their access within allowed boundaries. It also does not address broader infrastructure risks such as network-level attacks or failures in external dependencies. These areas require additional controls such as secure development practices, identity management, and network security measures. Recognizing these gaps ensures that future improvements can be prioritized appropriately and that risk is communicated transparently.
