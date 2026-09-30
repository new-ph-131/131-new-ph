allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // 🛡️ PREVENT ANDROIDX CRASHES ACROSS ALL PLUGINS
    configurations.all {
        resolutionStrategy.eachDependency {
            val group = requested.group
            val name = requested.name
            
            if (group == "androidx.core" && (name == "core" || name == "core-ktx")) {
                useVersion("1.13.1")
            }
            if (group == "androidx.activity" && (name == "activity" || name == "activity-ktx")) {
                useVersion("1.9.3")
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    // 🎯 THE FINAL 'lStar' FIX (Placed Correctly Before Evaluation)
    // यह सभी प्लगइन्स (जैसे mlkit) को मजबूर करेगा कि वे SDK 36 का ही इस्तेमाल करें 
    // जिससे lStar एरर ख़त्म हो जाएगा।
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(36)
            }
        }
    }
}

// ⚠️ DO NOT MOVE THIS UP (It must stay at the bottom)
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
