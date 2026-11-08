// Android autolinking.cpp에 C++ 모듈을 등록하는 설정
module.exports = {
  dependency: {
    platforms: {
      android: {
        cxxModuleCMakeListsModuleName: 'plyst_search',
        cxxModuleCMakeListsPath: 'CMakeLists.txt',
        cxxModuleHeaderName: 'PlystSearchModule',
      },
    },
  },
};
