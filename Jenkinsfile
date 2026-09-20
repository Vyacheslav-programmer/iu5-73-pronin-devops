pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        PYTHON = 'python3'
        PIP_DISABLE_PIP_VERSION_CHECK = '1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Setup Python') {
            steps {
                sh '''
                    ${PYTHON} --version
                    ${PYTHON} -m pip --version
                '''
            }
        }

        stage('Install dependencies') {
            steps {
                sh '''
                    ${PYTHON} -m pip install --upgrade pip
                    ${PYTHON} -m pip install -r requirements.txt
                    ${PYTHON} -m pip install -r requirements-dev.txt
                '''
            }
        }

        stage('Compilation Check') {
            steps {
                sh '${PYTHON} -m compileall server.py'
            }
        }

        stage('Linting') {
            steps {
                sh '${PYTHON} -m ruff check .'
            }
        }

        stage('Tests') {
            steps {
                sh '${PYTHON} -m pytest tests/ -v --tb=short'
            }
        }
    }

    post {
        success {
            echo 'Pipeline finished successfully'
        }
        failure {
            echo 'Pipeline failed'
        }
        always {
            echo "Build ${env.BUILD_NUMBER} completed with status ${currentBuild.currentResult}"
        }
    }
}
