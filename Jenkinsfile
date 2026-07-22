pipeline {
    agent {
        docker {
            image 'node:20'
            // Mount Docker socket to allow Docker commands within the container
            // Add host mapping for host.docker.internal to enable access to services running on the host machine
            args '-v /var/run/docker.sock:/var/run/docker.sock --add-host=host.docker.internal:host-gateway'
        }
    }

    environment {
    NODE_ENV  = 'test'
    BUILD_DIR = 'dist'
    APP_NAME  = 'kijanikiosk'
    NEXUS_URL = 'http://host.docker.internal:8081'
    NEXUS_REPO_NAME = 'npm-kijanikiosk'
    ARTIFACT_NAME   = 'kijanikiosk'
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Initialize Pipeline') {
            steps {
                script {
                    echo "Initializing Pipeline for ${APP_NAME}"
                    echo "Setting up environment variables"
                    env.PKG_VERSION = sh(script: 'node -p "require(\'./package.json\').version"', returnStdout: true).trim()
                    env.GIT_SHORT   = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.ARTIFACT_VERSION = "${env.PKG_VERSION}-${env.GIT_SHORT}"
                    env.APP_VERSION = env.PKG_VERSION
                }
            }
        }

        stage('Install Dependencies') {
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

        stage('Build Application') {
            steps {
                    
                    echo "Building version ${env.PKG_VERSION}"
                    sh 'npm run build'

                    echo "Check build output directory: ${env.BUILD_DIR}"
                    sh "ls -la ${env.BUILD_DIR} && [ \"\$(ls -A ${env.BUILD_DIR})\" ]"
                    
                    echo "Stashing build output for parallel stages"
                    stash includes: "${env.BUILD_DIR}/**", name: "build-output", useDefaultExcludes: true
                }
            }

        //  Parallel Verify stage (Test and Security Audit)
        stage('Verify Build') {
            parallel {
                stage('Test') {
                    steps {
                        
                        echo "Running Unit Tests"
                        unstash 'build-output'

                        // Generate JUnit XML for post-build analysis
                        sh 'npm run test -- --passWithNoTests --reporter=junit --outputFile=junit-results.xml'
                        
                    }
                    post {
                        always {
                            // Publish JUnit test results for analysis
                            junit allowEmptyResults: true, testResults: 'junit-results.xml'
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
        stage('Archive Artifacts') {
            steps {
                
                    echo "Archiving and Fingerprinting the Artifact"
                    archiveArtifacts artifacts: "${BUILD_DIR}/**",
                                 fingerprint: true,
                                 onlyIfSuccessful: true
                
            }
        }

        // Publish stage with secure Nexus authentication
        stage('Publish Artifacts') {
            steps {
                echo "Publishing ${ARTIFACT_NAME}@${APP_VERSION} to Nexus Repository"
                echo "Building artifact version: ${ARTIFACT_VERSION}"
                echo "Using NEXUS URL: ${NEXUS_URL}"
                echo "Target repository: ${NEXUS_REPO_NAME}"
                
                unstash 'build-output'
                
                    // withCredentials ensures secrets are masked and scoped to this block
                    withCredentials([usernamePassword(credentialsId: 'nexus-credentials-id', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
                        sh '''
                        set -e

                        trap 'rm -f .npmrc; echo ".npmrc securely deleted via trap"' EXIT

                        NEXUS_AUTH_TOKEN=$(echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64)
                        echo "Nexus token generated for secure authentication"

                        printf 'registry=%s/repository/%s/\n//%s/repository/%s/:_auth=%s\n' \
                            "$NEXUS_URL" "$NEXUS_REPO_NAME" \
                            "${NEXUS_URL#http://}" "$NEXUS_REPO_NAME" "$NEXUS_AUTH_TOKEN" > .npmrc

                        npm version "${ARTIFACT_VERSION}" --no-git-tag-version
                        echo "Publishing ${ARTIFACT_NAME}@${ARTIFACT_VERSION} to Nexus"
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
                echo "Published ${APP_NAME} version ${ARTIFACT_VERSION} to Nexus"
                echo "Artifact URL: ${NEXUS_URL}/${APP_NAME}/-/${APP_NAME}-${ARTIFACT_VERSION}.tgz"
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