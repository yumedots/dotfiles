#include "vmdisplay.h"
#include "qmp.h"
#include "inhibitor.h"

#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QOpenGLContext>
#include <QDebug>
#include <QTimer>
#include <QOpenGLFunctions>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QtQuick/qsgtexture_platform.h>
#include <QWheelEvent>
#include <QtGui/qopenglcontext_platform.h>
#include <QtGui/qguiapplication_platform.h>
#include <qpa/qplatformwindow_p.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <sys/mman.h>
#include <unistd.h>

namespace {

PFNEGLCREATEIMAGEKHRPROC createImage = nullptr;
PFNGLEGLIMAGETARGETTEXTURE2DOESPROC imageTarget = nullptr;
PFNEGLDESTROYIMAGEKHRPROC destroyImage = nullptr;

void loadEgl() {
	if (createImage && imageTarget && destroyImage) return;
	createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
	imageTarget = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));
	destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
}

int qnumForEvdev(int evdev) {
	switch (evdev) {
	case 1: return 0x01;
	case 2: return 0x02;
	case 3: return 0x03;
	case 4: return 0x04;
	case 5: return 0x05;
	case 6: return 0x06;
	case 7: return 0x07;
	case 8: return 0x08;
	case 9: return 0x09;
	case 10: return 0x0a;
	case 11: return 0x0b;
	case 12: return 0x0c;
	case 13: return 0x0d;
	case 14: return 0x0e;
	case 15: return 0x0f;
	case 16: return 0x10;
	case 17: return 0x11;
	case 18: return 0x12;
	case 19: return 0x13;
	case 20: return 0x14;
	case 21: return 0x15;
	case 22: return 0x16;
	case 23: return 0x17;
	case 24: return 0x18;
	case 25: return 0x19;
	case 26: return 0x1a;
	case 27: return 0x1b;
	case 28: return 0x1c;
	case 29: return 0x1d;
	case 30: return 0x1e;
	case 31: return 0x1f;
	case 32: return 0x20;
	case 33: return 0x21;
	case 34: return 0x22;
	case 35: return 0x23;
	case 36: return 0x24;
	case 37: return 0x25;
	case 38: return 0x26;
	case 39: return 0x27;
	case 40: return 0x28;
	case 41: return 0x29;
	case 42: return 0x2a;
	case 43: return 0x2b;
	case 44: return 0x2c;
	case 45: return 0x2d;
	case 46: return 0x2e;
	case 47: return 0x2f;
	case 48: return 0x30;
	case 49: return 0x31;
	case 50: return 0x32;
	case 51: return 0x33;
	case 52: return 0x34;
	case 53: return 0x35;
	case 54: return 0x36;
	case 55: return 0x37;
	case 56: return 0x38;
	case 57: return 0x39;
	case 58: return 0x3a;
	case 59: return 0x3b;
	case 60: return 0x3c;
	case 61: return 0x3d;
	case 62: return 0x3e;
	case 63: return 0x3f;
	case 64: return 0x40;
	case 65: return 0x41;
	case 66: return 0x42;
	case 67: return 0x43;
	case 68: return 0x44;
	case 87: return 0x57;
	case 88: return 0x58;
	case 96: return 0x60;
	case 97: return 0x61;
	case 98: return 0x62;
	case 99: return 0x63;
	case 100: return 0x64;
	case 102: return 0x66;
	case 103: return 0x67;
	case 104: return 0x68;
	case 105: return 0x69;
	case 106: return 0x6a;
	case 107: return 0x6b;
	case 108: return 0x6c;
	case 109: return 0x6d;
	case 110: return 0x6e;
	case 111: return 0x6f;
	case 113: return 0x71;
	case 114: return 0x72;
	case 115: return 0x73;
	case 116: return 0x74;
	case 117: return 0x75;
	case 118: return 0x76;
	case 119: return 0x77;
	case 121: return 0x79;
	case 122: return 0x7a;
	case 125: return 0x7d;
	case 126: return 0x7e;
	case 127: return 0x7f;
	default: return -1;
	}
}

} // namespace

struct VmDisplay::Private {
	QmpDisplay *display = nullptr;
	EGLDisplay eglDisplay = EGL_NO_DISPLAY;
	EGLImageKHR image = EGL_NO_IMAGE_KHR;
	GLuint texture = 0;
	int textureW = 0;
	int textureH = 0;
	bool y0top = false;
	QSGTexture *nodeTexture = nullptr;
	QImage cursorImage;
	WaylandInhibitor inhibitor;
	QMetaObject::Connection activeConnection;
};

VmDisplay::VmDisplay(QQuickItem *parent) : QQuickItem(parent), d(new Private) {
	setFlag(ItemHasContents, true);
	setAcceptedMouseButtons(Qt::AllButtons);
	setAcceptHoverEvents(true);
	d->display = new QmpDisplay(this);
	connect(d->display, &QmpDisplay::frameReady, this, [this]() { update(); });
	connect(d->display, &QmpDisplay::mapReady, this, [this]() { update(); });
	connect(d->display, &QmpDisplay::updated, this, [this]() { update(); });
	connect(d->display, &QmpDisplay::cursorImage, this, [this](const QImage &image, int hotX, int hotY) {
		d->cursorImage = image;
		setCursor(QCursor(QPixmap::fromImage(image), hotX, hotY));
	});
	connect(d->display, &QmpDisplay::mouseState, this, [this](int, int, bool visible) {
		setCursor(visible && !d->cursorImage.isNull() ? QCursor(QPixmap::fromImage(d->cursorImage)) : Qt::BlankCursor);
	});
	connect(d->display, &QmpDisplay::failed, this, [this](const QString &message) {
		m_error = message;
		m_running = false;
		emit errorChanged();
		emit runningChanged();
		QTimer::singleShot(1000, this, [this]() { maybeStart(); });
	});
}

VmDisplay::~VmDisplay() {
	if (d->nodeTexture) delete d->nodeTexture;
	if (d->texture) {
		QOpenGLContext *ctx = QOpenGLContext::currentContext();
		if (ctx) ctx->functions()->glDeleteTextures(1, &d->texture);
	}
	if (d->image != EGL_NO_IMAGE_KHR && d->eglDisplay != EGL_NO_DISPLAY) destroyImage(d->eglDisplay, d->image);
	delete d;
}

void VmDisplay::setQmp(const QString &value) {
	if (m_qmp == value) return;
	m_qmp = value;
	emit qmpChanged();
	maybeStart();
}

void VmDisplay::maybeStart() {
	if (m_qmp.isEmpty() || !window() || width() <= 0 || height() <= 0) return;
	if (m_running) return;
	const int w = qRound(width() * window()->devicePixelRatio());
	const int h = qRound(height() * window()->devicePixelRatio());
	if (w <= 0 || h <= 0) return;
	d->display->start(m_qmp, w, h);
	m_running = true;
	emit runningChanged();
}

void VmDisplay::geometryChange(const QRectF &next, const QRectF &prev) {
	QQuickItem::geometryChange(next, prev);
	if (next.size().toSize() == prev.size().toSize()) return;
	maybeStart();
	if (m_running && window()) {
		d->display->setUiInfo(qRound(width() * window()->devicePixelRatio()),
		                      qRound(height() * window()->devicePixelRatio()));
	}
	update();
}

void VmDisplay::itemChange(ItemChange change, const ItemChangeData &value) {
	QQuickItem::itemChange(change, value);
	if (change != ItemSceneChange) return;

	if (d->activeConnection) QObject::disconnect(d->activeConnection);

	QQuickWindow *win = value.window;
	if (!win) {
		d->inhibitor.inhibit(false);
		return;
	}

	const auto update = [this]() {
		QQuickWindow *window = this->window();
		if (!window) return;

		if (!window->isActive()) {
			d->inhibitor.inhibit(false);
			return;
		}

		auto *application = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
		auto *wayland = window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
		if (!application || !wayland) return;

		d->inhibitor.setSurface(application->display(), application->seat(), wayland->surface());
		d->inhibitor.inhibit(true);
		forceActiveFocus();
	};

	d->activeConnection = connect(win, &QQuickWindow::activeChanged, this, update);
	update();
}

void VmDisplay::mousePressEvent(QMouseEvent *event) {
	forceActiveFocus();
	sendMouse(event->position(), event->button(), true);
	event->accept();
}

void VmDisplay::mouseReleaseEvent(QMouseEvent *event) {
	sendMouse(event->position(), event->button(), false);
	event->accept();
}

void VmDisplay::mouseMoveEvent(QMouseEvent *event) {
	sendPosition(event->position());
	event->accept();
}

void VmDisplay::wheelEvent(QWheelEvent *event) {
	const int steps = event->angleDelta().y() / 120;
	for (int i = 0; i < qAbs(steps); i++) d->display->wheel(steps > 0);
	event->accept();
}

void VmDisplay::sendPosition(const QPointF &pos) {
	const int w = qRound(width() * (window() ? window()->devicePixelRatio() : 1));
	const int h = qRound(height() * (window() ? window()->devicePixelRatio() : 1));
	if (w <= 0 || h <= 0) return;
	int x = qBound(0, qRound(pos.x() * w / qMax(1.0, width())), w - 1);
	int y = qBound(0, qRound(pos.y() * h / qMax(1.0, height())), h - 1);
	d->display->mouseAbs(x, y);
}

void VmDisplay::sendMouse(const QPointF &pos, Qt::MouseButton button, bool down) {
	sendPosition(pos);
	int qbutton = 0;
	switch (button) {
	case Qt::LeftButton: qbutton = 0; break;
	case Qt::MiddleButton: qbutton = 1; break;
	case Qt::RightButton: qbutton = 2; break;
	default: return;
	}
	d->display->mouseButton(qbutton, down);
}

void VmDisplay::keyPressEvent(QKeyEvent *event) {
	if (event->isAutoRepeat()) {
		event->accept();
		return;
	}
	const int qnum = qnumForEvdev(int(event->nativeScanCode()) - 8);
	if (qnum >= 0) d->display->key(qnum, true);
	event->accept();
}

void VmDisplay::keyReleaseEvent(QKeyEvent *event) {
	if (event->isAutoRepeat()) {
		event->accept();
		return;
	}
	const int qnum = qnumForEvdev(int(event->nativeScanCode()) - 8);
	if (qnum >= 0) d->display->key(qnum, false);
	event->accept();
}

void VmDisplay::hoverEnterEvent(QHoverEvent *event) {
	forceActiveFocus();
	QQuickItem::hoverEnterEvent(event);
}

QSGNode *VmDisplay::updatePaintNode(QSGNode *node, UpdatePaintNodeData *) {
	if (!window()) return nullptr;
	QOpenGLContext *context = QOpenGLContext::currentContext();
	if (!context) return nullptr;
	auto *egl = context->nativeInterface<QNativeInterface::QEGLContext>();
	if (!egl) return nullptr;
	d->eglDisplay = egl->display();
	loadEgl();
	if (!createImage || !imageTarget) return nullptr;

	if (auto frame = d->display->takeFrame(); frame.fd >= 0) {
		if (frame.fd >= 0 && d->eglDisplay != EGL_NO_DISPLAY) {
			destroyImage(d->eglDisplay, d->image);
			d->image = EGL_NO_IMAGE_KHR;
		}
		if (frame.fd >= 0) {
			EGLint attrs[] = {
				EGL_WIDTH, frame.w,
				EGL_HEIGHT, frame.h,
				EGL_LINUX_DRM_FOURCC_EXT, EGLint(frame.fourcc),
				EGL_DMA_BUF_PLANE0_FD_EXT, frame.fd,
				EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGLint(frame.offset),
				EGL_DMA_BUF_PLANE0_PITCH_EXT, EGLint(frame.stride),
				EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGLint(frame.modLo),
				EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, EGLint(frame.modHi),
				EGL_NONE,
			};
			d->image = createImage(d->eglDisplay, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs);
			close(frame.fd);
		}
		if (frame.fd >= 0 && d->eglDisplay != EGL_NO_DISPLAY) {
			GLuint texture = 0;
			glGenTextures(1, &texture);
			glBindTexture(GL_TEXTURE_2D, texture);
			imageTarget(GL_TEXTURE_2D, d->image);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
			if (d->texture) context->functions()->glDeleteTextures(1, &d->texture);
			d->texture = texture;
			d->textureW = frame.w;
			d->textureH = frame.h;
			d->y0top = frame.y0top;
			if (d->nodeTexture) {
				delete d->nodeTexture;
				d->nodeTexture = nullptr;
			}
		}
	}

	if (auto map = d->display->takeMap(); map.fd >= 0) {
		if (map.w > 0 && map.h > 0 && map.stride > 0) {
			if (!d->texture) {
				glGenTextures(1, &d->texture);
				glBindTexture(GL_TEXTURE_2D, d->texture);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
			} else {
				glBindTexture(GL_TEXTURE_2D, d->texture);
			}
			void *data = mmap(nullptr, size_t(map.stride) * map.h, PROT_READ, MAP_SHARED, map.fd, map.offset);
			if (data != MAP_FAILED) {
				glPixelStorei(GL_UNPACK_ROW_LENGTH, map.stride / 4);
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, map.w, map.h, 0, GL_BGRA, GL_UNSIGNED_BYTE, data);
				glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
				munmap(data, size_t(map.stride) * map.h);
			}
			d->textureW = map.w;
			d->textureH = map.h;
			d->y0top = true;
			if (d->nodeTexture) {
				delete d->nodeTexture;
				d->nodeTexture = nullptr;
			}
		}
		close(map.fd);
	}

	auto *textureNode = static_cast<QSGSimpleTextureNode *>(node);
	if (!textureNode) textureNode = new QSGSimpleTextureNode;
	textureNode->setRect(boundingRect());
	if (!d->texture || d->textureW <= 0 || d->textureH <= 0) return textureNode;
	if (!d->nodeTexture) {
		d->nodeTexture = QNativeInterface::QSGOpenGLTexture::fromNative(d->texture, window(), QSize(d->textureW, d->textureH), QQuickWindow::TextureHasAlphaChannel);
	}
	textureNode->setTexture(d->nodeTexture);
	textureNode->setTextureCoordinatesTransform(d->y0top ? QSGSimpleTextureNode::MirrorVertically : QSGSimpleTextureNode::NoTransform);
	textureNode->markDirty(QSGNode::DirtyMaterial);
	return textureNode;
}
