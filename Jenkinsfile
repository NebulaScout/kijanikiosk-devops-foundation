pipeline {
    agent {
        docker {
            image 'node:18.19.1'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    // environment {
    //     NODE_ENV         = 'test'
    //     BUILD_DIR        = 'dist'  
    //     APP_NAME         = 'kijanikiosk-devops'
    //     PKG_VERSION      = sh(script: 'node -p "require(\'./package.json\').version"', returnStdout: true).trim()
    //     GIT_SHORT        = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim() 
    //     ARTIFACT_VERSION = "${PKG_VERSION}-${GIT_SHORT}" 
    //     NEXUS_URL        = 'http://localhost:8081/'
    //     APP_VERSION      = "${PKG_VERSION}"
    //     NEXUS_REPO_NAME = 'npm-kijanikiosk'
    //     ARTIFACT_NAME   = 'kijani-kiosk'
    // }

    environment {
    NODE_ENV  = 'test'
    BUILD_DIR = 'dist'
    APP_NAME  = 'kijanikiosk-devops'
    NEXUS_URL = 'http://localhost:8081/'
    NEXUS_REPO_NAME = 'npm-kijanikiosk'
    ARTIFACT_NAME   = 'kijani-kiosk'
}

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        // stage('Checkout') {
        //     steps {
        //         checkout scm
        //     }
        // }

        stage('Init') {
            steps {
                script {
                    env.PKG_VERSION = sh(script: 'node -p "require(\'./package.json\').version"', returnStdout: true).trim()
                    env.GIT_SHORT   = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.ARTIFACT_VERSION = "${env.PKG_VERSION}-${env.GIT_SHORT}"
                    env.APP_VERSION = env.PKG_VERSION
                }
            }
        }

        stage('Install') {
            steps {
                    echo "Installing all dependencies"
                    sh 'npm ci --no-audit --no-fund'
            }
        }

        // Lint stage before Build (Fail-Fast Principle)
        stage('Lint') {
            steps {
                    echo "Running ESLint on source files"
                    sh 'npm run lint'
            }
        }

        stage('Build') {
            steps {
                    
                    echo "Building version ${env.PKG_VERSION}"
                    sh 'npm run build'

                    echo "Check build output directory: ${env.BUILD_DIR}"
                    sh 'ls -la ${env.BUILD_DIR} && [ "$(ls -A ${env.BUILD_DIR})" ]'
                    
                    echo "Stashing build output for parallel stages"
                    stash includes: "${env.BUILD_DIR}/**", name: "build-output", useDefaultExcludes: true
                }
            }

        //  Parallel Verify stage (Test and Security Audit)
        stage('Verify') {
            parallel {
                stage('Test') {
                    steps {
                        
                        echo "Running Unit Tests"
                        unstash 'build-output'

                        // Generate JUnit XML for post-build analysis
                        sh 'npm run test -- --ci --reporters=default --reporters=jest-junit'
                        
                    }
                    post {
                        always {
                            // Publish JUnit test results for analysis
                            junit allowEmptyResults: true, testResults: '**/junit-*.xml'
                        }
                    }
                }

                stage('Security Audit') {
                    steps {
                        
                            echo "Running Security Audit (npm audit)"
                            unstash 'build-output'
                            // Fail build if high/critical vulnerabilities found
                            sh 'npm audit --audit-level=high'
                         
                    }
                }
            }
        }

        // Archive stage with artifact fingerprinting
        stage('Archive') {
            steps {
                
                    echo "Archiving and Fingerprinting the Artifact"
                    archiveArtifacts artifacts: "${BUILD_DIR}/**",
                                 fingerprint: true,
                                 onlyIfSuccessful: true
                
            }
        }

        // Publish stage with secure Nexus authentication
        stage('Publish') {
            steps {

                unstash 'build-output'
                
                    // withCredentials ensures secrets are masked and scoped to this block
                    withCredentials([usernamePassword(credentialsId: 'nexus-credentials-id', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                        sh '''
                        set -e

                        # This ensures .npmrc is deleted whether the script succeeds, fails, or is aborted
                        trap 'rm -f .npmrc; echo ".npmrc securely deleted via trap"' EXIT


                        NEXUS_AUTH_TOKEN=$(echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64)
                        echo "Nexus token generated for secure authentication"

                            # Create .npmrc dynamically within the shell step
                            cat > .npmrc <<EOF
                            registry=${NEXUS_URL}/repository/${NEXUS_REPO_NAME}/
                            //${NEXUS_URL#http://}/repository/${NEXUS_REPO_NAME}/:_auth=${NEXUS_AUTH_TOKEN}

                            EOF

                            echo "Publishing ${ARTIFACT_NAME}@${APP_VERSION} to Nexus"
                            npm publish --registry ${NEXUS_URL}/repository/${NEXUS_REPO_NAME}/
                        '''
                    }
                
            }
        }
    }

    // Comprehensive post block
    post {
        always {
            // Workspace cleanup to prevent disk exhaustion and cross-build contamination
            cleanWs()
            
        }
        success {
            
                // Log the specific artifact URL for downstream consumption
                echo "Published ${APP_NAME} version ${ARTIFACT_VERSION} to Nexus"
                echo "Artifact URL: ${NEXUS_URL}/kijanikiosk-payments/-/kijanikiosk-payments-${ARTIFACT_VERSION}.tgz"
        }
        failure {
            script {
                echo "Pipeline FAILED at build ${BUILD_NUMBER} - check logs at ${BUILD_URL}"

            }
        }
        changed {
            echo "Pipeline status changed from previous build - investigate potential issues"
        }
    }
}   