pipeline {
    agent any

    environment {
        PYTHON = 'python3'
        TMPDIR = '/root/tmp'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Setup Python') {
            steps {
                sh '${PYTHON} --version'
                sh '${PYTHON} -m pip --version'
            }
        }
        stage('Install dependencies') {
            steps {
                sh '''
                    mkdir -p ${TMPDIR}
                    ${PYTHON} -m pip install --cache-dir ${TMPDIR}/pip-cache -r requirements.txt
                    ${PYTHON} -m pip install --cache-dir ${TMPDIR}/pip-cache -r requirements-dev.txt
                '''
            }
        }
        stage('Compilation Check') {
            steps {
                sh """
                    ${PYTHON} -m py_compile server.py
                    ${PYTHON} -m py_compile voicegen.py
                    ${PYTHON} -m py_compile model_loader.py
                """
            }
        }
        stage('Linting') {
            steps {
                sh '${PYTHON} -m ruff check .'
            }
        }
        stage('TODO Check') {
            steps {
                sh 'bash ci-check.sh'
            }
        }
        stage('Unit Tests') {
            steps {
                sh '${PYTHON} -m pytest tests/ -v --tb=short'
            }
        }
        stage('Integration Tests') {
            steps {
                sh '${PYTHON} -m pytest tests/test_loadtest.py -v --tb=short'
            }
        }
        stage('Security Scan') {
            steps {
                sh '''
                    ${PYTHON} -m pip install bandit safety
                    ${PYTHON} -m bandit -r . -f json -o security-bandit.json -x ./venv,./.git || true
                    ${PYTHON} -m safety check --json > security-safety.json || true
                    echo "Security scan завершён"
                '''
            }
        }
        stage('Load Test') {
            steps {
                sh '${PYTHON} -m pytest tests/test_loadtest.py -v --tb=short'
            }
        }
        stage('Aggregate Report') {
            steps {
                sh 'bash aggregate-report.sh'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'report.md, security-bandit.json, security-safety.json', allowEmptyArchive: true
        }
        failure {
            echo 'Build failed. Check the console output for details.'
        }
        success {
            echo 'Build completed successfully.'
        }
    }
}
