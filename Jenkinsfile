@Library('platform-deploy-lib') _

pipeline {

    agent none

    options {
        timestamps()
        ansiColor('xterm')
    }

    parameters {

        string(
            name: 'PROJECT',
            defaultValue: '',
            description: 'Deploy only specific project (directory name)'
        )

        booleanParam(
            name: 'FORCE_DEPLOY',
            defaultValue: false,
            description: 'Force deploy ignoring change detection'
        )

        choice(
            name: 'DEPLOY_TARGET',
            choices: ['single', 'all'],
            description: 'Deploy to one cluster or all clusters'
        )

        choice(
            name: 'CLUSTER',
            choices: ['cloud', 'onprem'],
            description: 'Target cluster (used if single selected)'
        )
    }

    stages {

        stage('Checkout') {
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