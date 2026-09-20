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
        stage('Tests') {
            steps {
                sh '${PYTHON} -m pytest tests/ -v --tb=short'
            }
        }
    }

    post {
        failure {
            echo 'Build failed. Check the console output for details.'
        }
        success {
            echo 'Build completed successfully.'
        }
    }
}
