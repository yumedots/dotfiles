#include "plugin.h"
#include "vmdisplay.h"

void YudaeNativePlugin::registerTypes(const char *uri) {
	qmlRegisterType<VmDisplay>(uri, 1, 0, "VmDisplay");
}
