allprojects {
    repositories {
        google()
        mavenCentral()
        // Both official native billing SDKs used by iran_iap are distributed
        // through JitPack. Keep the repository permanently configured; the
        // selected store still controls which dependency is actually resolved.
        maven {
            url = uri("https://jitpack.io")
            content {
                includeGroup("com.github.cafebazaar.Poolakey")
                includeGroup("com.github.myketstore")
            }
        }
    }
}
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
