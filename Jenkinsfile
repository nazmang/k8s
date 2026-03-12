@Library('platform-deploy-lib@main') _

pipeline {

    agent none

    options {
        timestamps()
        ansiColor('xterm')
    }

    parameters {
        string(name: 'PROJECT', defaultValue: '', description: 'Optional: deploy only this project. Leave empty and use "Select project" stage to pick from repo.')
        booleanParam(name: 'FORCE_DEPLOY', defaultValue: false)
        choice(name: 'DEPLOY_TARGET', choices: ['single','all'])
        choice(name: 'CLUSTER', choices: ['cloud','onprem'])
        booleanParam(name: 'AUTOFILL_PROJECT', defaultValue: true, description: 'After checkout, show dropdown of projects (dirs with deploy.yaml) to choose from')
    }

    stages {

        stage('Checkout') {
            agent any
            steps {
                checkout scm
                script {
                    if (params.AUTOFILL_PROJECT) {
                        def choices = [''] + platformProjectChoices()
                        if (choices.size() > 1) {
                            def result = input(
                                message: 'Choose project to deploy',
                                parameters: [
                                    choice(name: 'PROJECT_SELECTED', choices: choices, description: 'Empty = use FORCE_DEPLOY or changed-only')
                                ]
                            )
                            env.PROJECT_SELECTED = result?.PROJECT_SELECTED ?: ''
                        }
                    }
                }
                stash name: 'workspace', includes: '**/*'
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
                                unstash 'workspace'
                                platformDeploy()
                            }
                        }
                    }
                }
            }
        }
    }
}
