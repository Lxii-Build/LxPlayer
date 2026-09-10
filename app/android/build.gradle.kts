// 不写 version：settings.gradle.kts 的 plugins 块已经把这两个插件放上了
// classpath，再写一次版本会直接报「已在 classpath 上的插件不得再指定版本」。
plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    repositories {
        // 阿里云镜像（加速国内下载）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Flutter 插件是以子工程形式编译的，app/build.gradle.kts 里的 compileOptions /
// kotlinOptions 只作用于 :app，管不到它们。没配置的模块会落回 Kotlin 默认的
// JVM 1.8，一旦某个插件（本次是 home_widget 0.9.0）要内联 JVM 11 的字节码就
// 会直接编译失败：
//   Cannot inline bytecode built with JVM target 11 into bytecode that is
//   being built with JVM target 1.8
// 所以这里统一把 Java 与 Kotlin 的目标版本都顶到 17，和 CI 上的 JDK 17 对齐。
// 两者必须一起改：只改 Kotlin 会触发「Inconsistent JVM-target compatibility」。
subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
    // 必须用 compilerOptions：Kotlin 2.2.20 起访问 kotlinOptions 不再是警告，
    // 而是直接判为编译错误（kotl.in/u1r8ln）。
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
