#pragma once

#include <QImage>
#include <QObject>
#include <QString>
#include <cstdint>
#include <memory>

class QmpDisplay : public QObject {
	Q_OBJECT

public:
	struct Frame {
		int fd = -1;
		uint32_t fourcc = 0;
		uint32_t modLo = 0;
		uint32_t modHi = 0;
		int x = 0;
		int y = 0;
		int w = 0;
		int h = 0;
		uint32_t offset = 0;
		uint32_t stride = 0;
		uint32_t bw = 0;
		uint32_t bh = 0;
		bool y0top = false;
	};

	struct Map {
		int fd = -1;
		int offset = 0;
		int w = 0;
		int h = 0;
		int stride = 0;
		uint32_t format = 0;
	};

	explicit QmpDisplay(QObject *parent = nullptr);
	~QmpDisplay() override;

	void start(const QString &qmpPath, int width, int height);
	void stop();
	void setUiInfo(int width, int height);
	void key(int qnum, bool down);
	void mouseAbs(int x, int y);
	void mouseButton(int button, bool down);
	void wheel(bool up);

	bool hasFrame() const;
	Frame takeFrame();
	Map takeMap();

signals:
	void frameReady();
	void mapReady();
	void updated(int x, int y, int w, int h);
	void cursorImage(const QImage &image, int hotX, int hotY);
	void mouseState(int x, int y, bool visible);
	void failed(const QString &message);

private:
	struct Impl;
	std::unique_ptr<Impl> d;
};
