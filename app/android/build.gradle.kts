// 不写 version：settings.gradle.kts 的 plugins 块已经把这两个插件放上了
// classpath，再写一次版本会直接报「已在 classpath 上的插件不得再指定版本」。
plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    // 这里刻意不配阿里云镜像：CI 跑在 GitHub 的境外 runner 上，镜像没有加速效果，
    // 而一旦它返回 502，Gradle 会把该仓库整个禁用，连锁出几十个
    // "Could not resolve" 导致构建失败（run 54 就是这么挂的）。
    repositories {
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
// 这里刻意不用 afterEvaluate：上面的 evaluationDependsOn(":app") 会提前把 :app
// 求值掉，再对它调 afterEvaluate 会直接抛
//   Cannot run Project.afterEvaluate(Action) when the project is already evaluated
// plugins.withId 没有这个问题——插件已应用就立刻回调，后应用则等应用时回调，
// 两种时机都能拿到 android 扩展。
subprojects {
    // :app 被上面的 evaluationDependsOn 提前求值过了，再对它注册 afterEvaluate
    // 会直接抛 "Cannot run Project.afterEvaluate(Action) when the project is
    // already evaluated"。它自己也有一套配套的 11/11，本来就不该动。
    if (state.executed) return@subprojects

    // 必须等插件自己的脚本跑完再覆盖：上一步试过 plugins.withId，它在插件「应用
    // 时刻」就回调，随后插件脚本里的 android { compileOptions } 会把 17 盖回 11，
    // 于是 :audio_session 出现 Java 11 / Kotlin 17 的不一致。afterEvaluate 才在
    // 子工程自身配置之后。
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
