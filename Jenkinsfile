@Library('platform-deploy-lib@main') _

pipeline {

    agent none

    options {
        timestamps()
        ansiColor('xterm')
    }

    parameters {
        string(name: 'PROJECT', defaultValue: '')
        booleanParam(name: 'FORCE_DEPLOY', defaultValue: false)
        choice(name: 'DEPLOY_TARGET', choices: ['single','all'])
        choice(name: 'CLUSTER', choices: ['cloud','onprem'])
    }

    stages {

        stage('Checkout') {
            agent any
            steps {
                checkout scm
            }
        }

        stage('Platform Deploy') {
            steps {
                script {

                    podTemplate(
                        label: 'k8s-deployer',
                        containers: [
                            containerTemplate(
                                name: 'deploy',
                                image: 'nazman/k8s-deployer:latest',
                                ttyEnabled: true,
                                command: 'cat'
                            )
                        ]
                    ) {

                        node('k8s-deployer') {

                            container('deploy') {
                                platformDeploy()
                            }
                        }
                    }
                }
            }
        }
    }
}