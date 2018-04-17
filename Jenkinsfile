@Library('jenkins-libs')
import ru.etecar.Libs
import ru.etecar.HelmClient
import ru.etecar.HelmRelease
import ru.etecar.HelmRepository
import java.time.ZonedDateTime
import static java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME
import static java.time.format.DateTimeFormatter.BASIC_ISO_DATE

def imageTag = ""
def buildNeeded = true
def pbfRepository = "http://download.geofabrik.de/russia-latest.osm.pbf"
def imageRepo = 'eu.gcr.io/indigo-terra-120510'
def appName = 'osrm-backend-docker-embdata'
def lastImageTime

@NonCPS
String getLastPbfTimestamp(String url) {
    def baseUrl = new URL(url);
    HttpURLConnection connection = (HttpURLConnection) baseUrl.openConnection();
    connection.addRequestProperty("Accept", "application/json");
    connection.with {
        doOutput = false
        requestMethod = 'GET'
    }
    return connection.getHeaderField("Last-Modified");
}

node('gce-standard-4-ssd'){
    cleanWs()
    checkout scm
    stage ('Build image') {
        try {
            copyArtifacts filter: 'pbf-timestamp', fingerprintArtifacts: true, projectName: "${env.JOB_NAME}", selector: lastSuccessful()
            lastImageTime = sh returnStdout: true, script: 'cat pbf-timestamp'
        }
        catch (e){
            echo "Assuming that it's first time build"
            lastImageTime = "Mon, 5 Jan 1970 00:00:00 GMT"
        }
        
        def lastModefied = getLastPbfTimestamp(pbfRepository);
        echo "lastModefied: ${lastModefied}"
        previousPbfDate = ZonedDateTime.parse(lastImageTime, RFC_1123_DATE_TIME);
        echo "previousPbfDate: ${previousPbfDate.format(RFC_1123_DATE_TIME)}"
        ZonedDateTime pbfDate = ZonedDateTime.parse(lastModefied, RFC_1123_DATE_TIME);
        
        if (!pbfDate.isAfter(previousPbfDate)) {
            throw new Exception("no changes in geofabric repo. No build needed");
        }
        
        imageTag = "russia-${pbfDate.format(BASIC_ISO_DATE)}";
        sh "echo -n \"${pbfDate.format(RFC_1123_DATE_TIME)}\"> pbf-timestamp"
        archiveArtifacts 'pbf-timestamp'
        withCredentials([file(credentialsId: 'google-docker-repo', variable: 'CREDENTIALS')]) {
            sh "mkdir -p ~/.docker && cat \"${CREDENTIALS}\" > ~/.docker/config.json"
        }
        docker.withRegistry("${imageRepo}"){
            def appImage = docker.build("${appName}:${imageTag}")
            appImage.push()
        }
    }
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

        stage('Build helm package'){
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