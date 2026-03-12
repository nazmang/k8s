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
        booleanParam(name: 'SKIP_PROJECT_INPUT', defaultValue: true, description: 'Skip project selection; deploy only changed projects (or all if FORCE_DEPLOY)')
    }

    stages {

        stage('Checkout') {
            agent any
            steps {
                checkout scm
                script {
                    if (params.AUTOFILL_PROJECT && !params.SKIP_PROJECT_INPUT) {
                        def dirs = sh(script: "ls -d */ 2>/dev/null | sed 's#/##'", returnStdout: true).trim().split("\n").findAll { it?.trim() }
                        def choices = [''] + dirs.findAll { fileExists("${it}/deploy.yaml") }
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
                        serviceAccount: 'jenkins',
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
                                platformDeploy(projectOverride: env.PROJECT_SELECTED)
                            }
                        }
                    }
                }
            }
        }
    }
}
