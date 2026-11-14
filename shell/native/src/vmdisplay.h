#pragma once

#include <QtQml/qqmlregistration.h>
#include <QQuickItem>
#include <QString>

class QmpDisplay;
class QTimer;

class VmDisplay : public QQuickItem {
	Q_OBJECT
	QML_ELEMENT
	Q_PROPERTY(QString qmp READ qmp WRITE setQmp NOTIFY qmpChanged)
	Q_PROPERTY(bool running READ running NOTIFY runningChanged)
	Q_PROPERTY(int guestWidth READ guestWidth NOTIFY guestSizeChanged)
	Q_PROPERTY(int guestHeight READ guestHeight NOTIFY guestSizeChanged)
	Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
	explicit VmDisplay(QQuickItem *parent = nullptr);
	~VmDisplay() override;

	QString qmp() const { return m_qmp; }
	void setQmp(const QString &value);
	bool running() const { return m_running; }
	int guestWidth() const { return m_guestWidth; }
	int guestHeight() const { return m_guestHeight; }
	QString error() const { return m_error; }

	QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *) override;

signals:
	void qmpChanged();
	void runningChanged();
	void guestSizeChanged();
	void errorChanged();

protected:
	void geometryChange(const QRectF &next, const QRectF &prev) override;
	void itemChange(ItemChange change, const ItemChangeData &value) override;
	void mousePressEvent(QMouseEvent *event) override;
	void mouseReleaseEvent(QMouseEvent *event) override;
	void mouseMoveEvent(QMouseEvent *event) override;
	void wheelEvent(QWheelEvent *event) override;
	void hoverEnterEvent(QHoverEvent *event) override;
	void hoverMoveEvent(QHoverEvent *event) override;
	void hoverLeaveEvent(QHoverEvent *event) override;
	void keyPressEvent(QKeyEvent *event) override;
	void keyReleaseEvent(QKeyEvent *event) override;

private:
	void maybeStart();
	void updateInhibitor();
	bool insideImage(const QPointF &pos) const;
	void sendPosition(const QPointF &pos);
	void flushPosition();
	void sendMouse(const QPointF &pos, Qt::MouseButton button, bool down);

	struct Private;
	Private *d = nullptr;

	QString m_qmp;
	bool m_running = false;
	int m_guestWidth = 0;
	int m_guestHeight = 0;
	QString m_error;
	QTimer *m_mouseTimer = nullptr;
	QPointF m_pendingPos;
	bool m_hasPending = false;
};
