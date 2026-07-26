pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "rising-padel-watch"

include(":mobile")
include(":wear")

// `core` es un build independiente para que sus tests corran sin el SDK de Android.
// La sustitución de dependencias la resuelve Gradle por coordenadas (com.risingpadel:core).
includeBuild("core")
