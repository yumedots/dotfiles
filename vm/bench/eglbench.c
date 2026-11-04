#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif
#ifndef EGL_PLATFORM_WAYLAND_KHR
#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#endif

static struct wl_compositor *compositor;

static void onGlobal(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
	(void)data;
	if (strcmp(interface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, version < 4 ? version : 4);
}

static void onGlobalRemove(void *data, struct wl_registry *registry, uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registryListener = { onGlobal, onGlobalRemove };

static double now(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static GLuint compile(GLenum type, const char *src) {
	GLuint shader = glCreateShader(type);
	glShaderSource(shader, 1, &src, NULL);
	glCompileShader(shader);
	GLint ok = 0;
	glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[4096];
		glGetShaderInfoLog(shader, sizeof(log), NULL, log);
		fprintf(stderr, "shader: %s\n", log);
		exit(1);
	}
	return shader;
}

static GLuint program(const char *vs, const char *fs) {
	GLuint p = glCreateProgram();
	glAttachShader(p, compile(GL_VERTEX_SHADER, vs));
	glAttachShader(p, compile(GL_FRAGMENT_SHADER, fs));
	glLinkProgram(p);
	GLint ok = 0;
	glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) {
		char log[4096];
		glGetProgramInfoLog(p, sizeof(log), NULL, log);
		fprintf(stderr, "link: %s\n", log);
		exit(1);
	}
	return p;
}

static const char *VS =
	"attribute vec2 aPos;\n"
	"uniform vec2 uOffset;\n"
	"uniform float uScale;\n"
	"void main() { gl_Position = vec4(aPos * uScale + uOffset, 0.0, 1.0); }\n";

static const char *HEAVY_FS =
	"precision highp float;\n"
	"uniform float uTime;\n"
	"void main() {\n"
	"  vec2 p = gl_FragCoord.xy * 0.0015 + uTime;\n"
	"  float v = 0.0;\n"
	"  for (int i = 0; i < 256; i++) {\n"
	"    p = vec2(p.x + sin(p.y * 1.3 + float(i) * 0.013),\n"
	"             p.y + cos(p.x * 1.7 + float(i) * 0.017));\n"
	"    v += sin(p.x * p.y);\n"
	"  }\n"
	"  gl_FragColor = vec4(0.5 + 0.5 * sin(v), 0.5 + 0.5 * cos(v), 0.5 + 0.5 * sin(v * 0.5), 1.0);\n"
	"}\n";

static const char *FLAT_FS =
	"precision mediump float;\n"
	"uniform vec4 uColor;\n"
	"void main() { gl_FragColor = uColor; }\n";

static void report(const char *label, int frames, int draws, double secs) {
	printf("%s: %d frames%s in %.3f s = %.1f fps", label, frames,
	       draws > 1 ? "" : "", secs, frames / secs);
	if (draws > 1) printf(", %.0f draws/s", frames * (double)draws / secs);
	printf("\n");
	fflush(stdout);
}

int main(int argc, char **argv) {
	int shaderFrames = argc > 1 ? atoi(argv[1]) : 240;
	int callFrames = argc > 2 ? atoi(argv[2]) : 120;
	int callDraws = argc > 3 ? atoi(argv[3]) : 4096;
	if (shaderFrames <= 0) shaderFrames = 240;
	if (callFrames <= 0) callFrames = 120;
	if (callDraws <= 0) callDraws = 4096;

	PFNEGLGETPLATFORMDISPLAYEXTPROC getPlatformDisplay =
		(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (!getPlatformDisplay) {
		fprintf(stderr, "no eglGetPlatformDisplayEXT\n");
		return 1;
	}

	struct wl_display *wl = wl_display_connect(NULL);
	struct wl_surface *surface = NULL;
	if (wl) {
		struct wl_registry *registry = wl_display_get_registry(wl);
		wl_registry_add_listener(registry, &registryListener, NULL);
		wl_display_roundtrip(wl);
		if (compositor) surface = wl_compositor_create_surface(compositor);
	}

	EGLDisplay dpy = EGL_NO_DISPLAY;
	if (wl && surface) dpy = getPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, wl, NULL);
	if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) {
		dpy = getPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
		if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) {
			fprintf(stderr, "eglInitialize failed 0x%x\n", eglGetError());
			return 1;
		}
	}
	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		fprintf(stderr, "eglBindAPI failed\n");
		return 1;
	}

	EGLint attrs[] = {
		EGL_SURFACE_TYPE, surface ? EGL_WINDOW_BIT : EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_NONE
	};
	EGLConfig cfg;
	EGLint count = 0;
	if (!eglChooseConfig(dpy, attrs, &cfg, 1, &count) || count == 0) {
		attrs[11] = 0;
		if (!eglChooseConfig(dpy, attrs, &cfg, 1, &count) || count == 0) {
			fprintf(stderr, "no EGL config\n");
			return 1;
		}
	}
	printf("config alpha: %d\n", attrs[11]);
	fflush(stdout);

	EGLint ctxAttrs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLSurface eglSurface = EGL_NO_SURFACE;
	if (surface) eglSurface = eglCreateWindowSurface(dpy, cfg, (EGLNativeWindowType)surface, NULL);
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttrs);
	if (ctx == EGL_NO_CONTEXT ||
	    !eglMakeCurrent(dpy, eglSurface, eglSurface, ctx)) {
		fprintf(stderr, "context failed 0x%x\n", eglGetError());
		return 1;
	}

	printf("renderer: %s\n", glGetString(GL_RENDERER));
	printf("version:  %s\n", glGetString(GL_VERSION));
	fflush(stdout);

	const int W = 1920, H = 1080;
	GLuint tex, fbo;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		fprintf(stderr, "incomplete fbo\n");
		return 1;
	}
	glViewport(0, 0, W, H);

	GLuint heavy = program(VS, HEAVY_FS);
	GLuint flat = program(VS, FLAT_FS);

	GLuint vbo;
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	float full[] = { -1, -1, 3, -1, -1, 3 };
	glBufferData(GL_ARRAY_BUFFER, sizeof(full), full, GL_STATIC_DRAW);
	GLint aPos = glGetAttribLocation(heavy, "aPos");
	glEnableVertexAttribArray(aPos);
	glVertexAttribPointer(aPos, 2, GL_FLOAT, GL_FALSE, 0, 0);

	glUseProgram(heavy);
	GLint hOffset = glGetUniformLocation(heavy, "uOffset");
	GLint hScale = glGetUniformLocation(heavy, "uScale");
	GLint hTime = glGetUniformLocation(heavy, "uTime");
	glUniform2f(hOffset, 0, 0);
	glUniform1f(hScale, 1);
	for (int i = 0; i < 8; i++) {
		glClear(GL_COLOR_BUFFER_BIT);
		glUniform1f(hTime, i * 0.01f);
		glDrawArrays(GL_TRIANGLES, 0, 3);
	}
	glFinish();

	double t0 = now();
	for (int i = 0; i < shaderFrames; i++) {
		glClear(GL_COLOR_BUFFER_BIT);
		glUniform1f(hTime, i * 0.001f);
		glDrawArrays(GL_TRIANGLES, 0, 3);
	}
	glFinish();
	report("heavy", shaderFrames, 1, now() - t0);

	float tri[] = { -0.012f, -0.012f, 0.012f, -0.012f, 0.0f, 0.012f };
	glBufferData(GL_ARRAY_BUFFER, sizeof(tri), tri, GL_STATIC_DRAW);
	glUseProgram(flat);
	aPos = glGetAttribLocation(flat, "aPos");
	glEnableVertexAttribArray(aPos);
	glVertexAttribPointer(aPos, 2, GL_FLOAT, GL_FALSE, 0, 0);
	GLint fOffset = glGetUniformLocation(flat, "uOffset");
	GLint fColor = glGetUniformLocation(flat, "uColor");
	GLint fScale = glGetUniformLocation(flat, "uScale");
	glUniform1f(fScale, 1);
	for (int i = 0; i < 32; i++) {
		glUniform2f(fOffset, (i % 8) * 0.2f - 0.7f, (i / 8) * 0.2f - 0.7f);
		glDrawArrays(GL_TRIANGLES, 0, 3);
	}
	glFinish();

	t0 = now();
	for (int f = 0; f < callFrames; f++) {
		glClear(GL_COLOR_BUFFER_BIT);
		for (int i = 0; i < callDraws; i++) {
			glUniform2f(fOffset, (i % 64) * 0.03f - 0.96f, ((i / 64) % 32) * 0.06f - 0.96f);
			glUniform4f(fColor, (i & 7) / 7.0f, (i & 15) / 15.0f, (i & 31) / 31.0f, 1);
			glDrawArrays(GL_TRIANGLES, 0, 3);
		}
	}
	glFinish();
	report("draws", callFrames, callDraws, now() - t0);

	eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(dpy, ctx);
	if (eglSurface != EGL_NO_SURFACE) eglDestroySurface(dpy, eglSurface);
	eglTerminate(dpy);
	if (surface) wl_surface_destroy(surface);
	if (compositor) wl_compositor_destroy(compositor);
	if (wl) wl_display_disconnect(wl);
	return 0;
}
