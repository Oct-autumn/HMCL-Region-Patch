package io.github.octautumn.hmclpatch;

import java.lang.instrument.Instrumentation;

/**
 * HMCL 区域补丁的 Java agent 入口。
 * <p>
 * 用法（Windows 官方 exe）：
 * <pre>set HMCL_JAVA_OPTS=-javaagent:D:\path\hmcl-region-patch.jar</pre>
 * <p>
 * 用法（jar 版 / Linux）：
 * <pre>java -javaagent:/path/hmcl-region-patch.jar -jar HMCL.jar</pre>
 * <p>
 * 在 premain 阶段注册 {@link RegionUtilsTransformer}，HMCL 之后加载
 * {@code org.jackhuang.hmcl.util.RegionUtils} 时会走改写逻辑。
 * 由于 premain 早于所有应用类加载，不需要 retransform，也不需要等 HMCL 初始化。
 */
public final class HMCLRegionPatchAgent {

    public static void premain(String agentArgs, Instrumentation instrumentation) {
        PatchLogger.init(agentArgs);

        PatchLogger.info("HMCL Region Patch 已注入（Java " + System.getProperty("java.version")
                + "，参数：" + (agentArgs == null || agentArgs.isBlank() ? "无" : agentArgs) + "）");

        try {
            instrumentation.addTransformer(new RegionUtilsTransformer());
            PatchLogger.info("ClassFileTransformer 已注册，等待 RegionUtils 类加载");
        } catch (Throwable throwable) {
            // 注册失败就什么都不做，让 HMCL 正常启动（只是补丁不生效）
            PatchLogger.error("注册 ClassFileTransformer 失败，补丁不会生效", throwable);
        }
    }

    private HMCLRegionPatchAgent() {
    }
}
