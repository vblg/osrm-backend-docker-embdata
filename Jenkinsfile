@Library('jenkins-libs')
import ru.etecar.Libs
import ru.etecar.HelmClient
import ru.etecar.HelmRelease
import ru.etecar.HelmRepository

def imageTag = ""
def buildNeeded = true
def pbfRepository = "http://download.geofabrik.de/russia-latest.osm.pbf"
def imageRepo = 'eu.gcr.io/indigo-terra-120510'
def appName = 'osrm-backend-docker-embdata'

node('gce-standard-4-ssd'){
    cleanWs()
    def lastImageTime = "0"
    stage ('Build image') {
        try {
            copyArtifacts filter: 'pbf-timestamp', fingerprintArtifacts: true, projectName: '${env.JOB_NAME}', selector: lastSuccessful()
            lastImageTime = sh returnStdout: true, script: 'cat pbf-timestamp'
        }
        catch (e){
            echo "Assuming that is first time build, because there is no artifacts"
            lastImageTime = "0"
        }
        def pbfDate = sh returnStdout: true, script: "DATE_MODIFIED=`curl -s -I ${pbfRepository}|grep Last-Modified|cut -d: -f2-|cut -d' ' -f2-6` && echo -n `date -d\"\$DATE_MODIFIED\" +%s`"
        if (pbfDate.toInteger() < lastImageTime.toInteger()) {
            imageTag = sh returnStdout: true, script: "echo -n \"russia-`date -d@${lastImageTime} +%Y%m%d`\" > pbf-timestamp && cat pbf-timestamp"
            archiveArtifacts 'pbf-timestamp'
            withCredentials([file(credentialsId: 'google-docker-repo', variable: 'CREDENTIALS')]) {
                sh "mkdir -p ~/.docker && cat \"${CREDENTIALS}\" > ~/.docker/config.json"
            }
            docker.withRegistry("${imageRepo}"){
                def appImage = docker.build("${appName}:${imageTag}")
                appImage.push()
            }            
        }
        else {
            echo "No changes in geofabric repo. No build needed"
            buildNeeded = false
        }        
    }
}
if ( ! buildNeeded ){
    currentBuild.result = 'FAILED'
    return
}

node ('docker-server'){
    Libs utils = new Libs(steps)
    HelmClient helm = new HelmClient(steps)
    HelmRepository repo = new HelmRepository(steps,"helmrepo","https://nexus:8443/repository/helmrepo/")
    try {
        cleanWs()
        kubeProdContext = "google-system"

        checkout scm
        helm.init('helm')
        helm.repoAdd(repo)

        stage('Build'){
            withCredentials([usernameColonPassword(credentialsId: "nexus", variable: 'CREDENTIALS')]) {
                repo.push(helm.buildPacket("helm/${appName}/Chart.yaml"), CREDENTIALS, "helm-repo")
            }
        }

        stage ('Production') {
            def stage = "production"
            def apiProdHostname = "maps.etecar.ru"
            HelmRelease osrmRelease = new HelmRelease(steps, "${appName}", "helmrepo/${appName}")

            try {
                helm.tillerNamespace = "kube-system"
                helm.kubeContext = kubeProdContext

                osrmRelease.namespace = "${stage}"
                osrmRelease.values = [
                        "ingress.enabled":"true",
                        "ingress.hosts[0]":"${ apiProdHostname}",
                        "image.tag" : "${imageTag}"
                ]
                helm.upgrade( osrmRelease )
                helm.waitForDeploy(osrmRelease, 400)
            } catch (e) {
                helm.rollback(osrmRelease)
                throw e
            }
        }
    } catch (e) {
        utils.sendMail("${env.JOB_NAME} (${env.BUILD_NUMBER}) has finished with FAILED", "See ${env.BUILD_URL}")
        throw e
    }
}