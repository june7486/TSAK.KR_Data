// 비웹(모바일·데스크톱 네이티브)용 스텁.
bool get isWebRuntime => false;

/// 웹이 아닌 환경에서는 아무 것도 하지 않는다.
void openUrlInTab(String url) {}
