// `core` es un build independiente (composite build) a propósito: así sus tests se
// ejecutan con `gradle -p android/core test` sin necesitar el SDK de Android ni el
// Android Gradle Plugin. Las apps :mobile y :wear lo consumen vía includeBuild.
rootProject.name = "core"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}
