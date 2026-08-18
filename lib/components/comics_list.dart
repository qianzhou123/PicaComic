part of 'components.dart';

class ComicsPageLogic<T> extends StateController {
  bool loading = true;

  ///用于正常模式下的漫画数据储存
  List<T>? comics;

  ///用于分页模式下的漫画数据储存
  Map<int, List<T>>? dividedComics;

  ///错误信息, null表示没有错误
  String? message;

  /// 最大页数, 为null表示不知道或者无穷
  int? maxPage;

  ///当前的页面序号
  int current = 1;

  ///是否正在获取数据， 用于在顺序浏览模式下， 避免同时进行多个网络请求
  bool loadingData = false;

  bool showFloatingButton = true;

  ///是否处于多选模式
  bool selecting = false;

  ///已选中的漫画在列表中的下标
  final Set<int> selected = {};

  int get selectedCount => selected.length;

  void enterSelectMode() {
    selecting = true;
    update();
  }

  void exitSelectMode() {
    selecting = false;
    selected.clear();
    update();
  }

  void toggleSelect(int index) {
    if (!selected.remove(index)) {
      selected.add(index);
    }
    update();
  }

  void selectAll(int count) {
    selected
      ..clear()
      ..addAll(List<int>.generate(count, (i) => i));
    update();
  }

  void get(Future<Res<List<T>>> Function(int) getComics) async {
    if (loadingData) return;
    loadingData = true;
    Future.microtask(() => update());
    if (comics == null) {
      var res = await getComics(1);
      if (res.error) {
        message = res.errorMessage;
      } else {
        comics = res.data;
        dividedComics = {};
        dividedComics![1] = res.data;
        if (res.subData is int) {
          maxPage = res.subData;
        }
        if (res.data.isEmpty) {
          maxPage = 1;
        }
      }
      loading = false;
      loadingData = false;
      update();
    } else {
      var res = await getComics(current);
      if (res.error) {
        message = res.errorMessage;
      } else {
        dividedComics![current] = res.data;
      }
      loading = false;
      loadingData = false;
      update();
    }
  }

  int _emptyPageCount = 0;

  void loadNextPage(Future<Res<List<T>>> Function(int) getComics) async {
    if (maxPage != null && current >= maxPage!) return;
    if (loadingData) return;
    loadingData = true;
    Future.microtask(() => update());
    var res = await getComics(current + 1);
    if (res.error) {
      showToast(message: res.errorMessage!);
    } else {
      if (res.subData is int) {
        maxPage = res.subData;
      }
      if (res.data.isEmpty) {
        _emptyPageCount++;
        if (_emptyPageCount > 3 && maxPage == null) {
          // 某些漫画源不会返回总页数, 而app的网络代码会根据用户设置进行屏蔽操作
          // 空页面既可能是因为没有更多页面, 也可能是因为被屏蔽了
          // 如果连续3次加载空页面, 则认为已经加载完毕
          maxPage = current;
        }
        // 等待一会儿再加载, 避免因为某些错误导致无限加载
        await Future.delayed(const Duration(seconds: 1));
      } else {
        _emptyPageCount = 0;
        comics!.addAll(res.data);
      }
    }
    current++;
    loadingData = false;
    update();
  }

  @override
  void refresh() {
    loading = true;
    comics = null;
    message = null;
    selected.clear();
    update();
  }
}

/// 漫画列表页面
///
/// T为漫画信息模型
abstract class ComicsPage<T extends BaseComic> extends StatelessWidget {
  const ComicsPage({super.key});

  ///标题
  String? get title;

  /// 是否居中标题
  bool get centerTitle => true;

  /// 获取图片, 参数为页面序号, **从1开始**
  ///
  /// 返回值Res的subData为页面总数
  Future<Res<List<T>>> getComics(int i);

  /// 漫画源标识符
  String get sourceKey;

  /// 显示一个刷新按钮, 需要Scaffold启用
  bool get withRefreshFloatingButton => false;

  String? get tag;

  Widget? get tailing => null;

  Widget? get header => null;

  bool get showPageIndicator => true;

  List<ComicTileMenuOption>? get addonMenuOptions => null;

  /// 刷新页面
  void refresh() {
    StateController.find<ComicsPageLogic<T>>(tag: tag).refresh();
  }

  @override
  Widget build(context) {
    Widget body = StateBuilder<ComicsPageLogic<T>>(
        init: ComicsPageLogic<T>(),
        tag: tag,
        builder: (logic) {
          return _withSelectionBar(context, logic, _buildBody(context, logic));
        });

    if (header != null && UiMode.m1(context)) {
      body = SafeArea(
        bottom: false,
        child: body,
      );
    }

    if (withRefreshFloatingButton) {
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.refresh),
          onPressed: () {
            refresh();
          },
        ),
        body: body,
      );
    } else {
      return Material(
        child: body,
      );
    }
  }

  Widget? _removeSliver(Widget? widget) {
    if (widget == null) return null;

    if (widget is SliverToBoxAdapter) {
      return widget.child;
    }

    if (widget is SliverPersistentHeader) {
      return SizedBox(
        height: widget.delegate.minExtent,
        child: widget.delegate.build(
          App.globalContext!,
          widget.delegate.minExtent,
          false,
        ),
      );
    }

    return widget;
  }

  /// 当前页面展示出的漫画列表(去除被屏蔽的作品)
  List<T> _currentComics(ComicsPageLogic logic) {
    List<T> list;
    if (appdata.settings[25] == "0") {
      list = (logic.comics ?? const []).cast<T>();
    } else {
      list = (logic.dividedComics?[logic.current] ?? const []).cast<T>();
    }
    if (appdata.appSettings.fullyHideBlockedWorks) {
      return list.where((comic) => isBlocked(comic) == null).toList();
    }
    return list;
  }

  Widget _buildBody(BuildContext context, ComicsPageLogic logic) {
    if (logic.dividedComics?[logic.current] == null &&
        logic.message == null &&
        appdata.settings[25] != "0") {
      logic.loading = true;
    }
    if (logic.loading) {
      logic.get(getComics);
      return Column(
        children: [
          if (title != null) const Appbar(title: Text("")),
          _removeSliver(header) ?? const SizedBox(),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        ],
      );
    } else if (logic.message != null) {
      return Column(
        children: [
          _removeSliver(header) ?? const SizedBox(),
          Expanded(
              child: NetworkError(
            message: logic.message ?? "Network Error",
            retry: logic.refresh,
            withAppbar: title != null,
          ))
        ],
      );
    } else {
      if (appdata.settings[25] == "0") {
        List<T> comics = _currentComics(logic);
        if (comics.isEmpty) {
          return SmoothCustomScrollView(
            slivers: [
              if (title != null) _buildAppbar(context, logic),
              if (header != null) header!,
              SliverFillRemaining(
                hasScrollBody: false,
                child: buildEmptyView(context),
              ),
            ],
          );
        }
        return SmoothCustomScrollView(
          slivers: [
            if (title != null) _buildAppbar(context, logic),
            if (header != null) header!,
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                  childCount: comics.length, (context, i) {
                if (i == comics.length - 1) {
                  logic.loadNextPage(getComics);
                }
                return _buildItemWithSelection(context, comics[i], i, logic);
              }),
              gridDelegate: SliverGridDelegateWithComics(),
            ),
            if (logic.current < (logic.maxPage ?? 114514) && logic.loadingData)
              const SliverToBoxAdapter(
                child: ListLoadingIndicator(),
              )
            else
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 80,
                ),
              )
          ],
        );
      } else {
        List<T> comics = _currentComics(logic);
        if (comics.isEmpty) {
          return SmoothCustomScrollView(
            slivers: [
              if (title != null) _buildAppbar(context, logic),
              if (header != null) header!,
              SliverFillRemaining(
                hasScrollBody: false,
                child: buildEmptyView(context),
              ),
            ],
          );
        }
        Widget body = SmoothCustomScrollView(
          slivers: [
            if (title != null) _buildAppbar(context, logic),
            if (header != null) header!,
            if (showPageIndicator &&
                appdata.settings[64] == "0" &&
                logic.maxPage != 1)
              buildPageSelector(context, logic),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                  childCount: comics.length, (context, i) {
                return _buildItemWithSelection(context, comics[i], i, logic);
              }),
              gridDelegate: SliverGridDelegateWithComics(),
            ),
            if (showPageIndicator &&
                appdata.settings[64] == "0" &&
                logic.maxPage != 1)
              buildPageSelector(context, logic),
            SliverPadding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom))
          ],
        );

        body = NotificationListener<ScrollUpdateNotification>(
          onNotification: (notifications) {
            if (notifications.scrollDelta != null) {
              if (notifications.scrollDelta! > 0 && logic.showFloatingButton) {
                logic.showFloatingButton = false;
                logic.update();
              } else if ((notifications.scrollDelta! < 0 ||
                      notifications.metrics.pixels ==
                          notifications.metrics.minScrollExtent ||
                      notifications.metrics.pixels ==
                          notifications.metrics.maxScrollExtent) &&
                  !logic.showFloatingButton) {
                logic.showFloatingButton = true;
                logic.update();
              }
            }
            return false;
          },
          child: body,
        );

        if (showPageIndicator && appdata.settings[64] == "1") {
          return Stack(
            children: [
              Positioned.fill(
                child: body,
              ),
              Positioned(
                left: 0,
                right: 12,
                top: 0,
                bottom: 0,
                child: buildPageSelectorRight(context, logic),
              )
            ],
          );
        } else {
          return body;
        }
      }
    }
  }

  /// 多选模式下的顶栏
  Widget _buildAppbar(BuildContext context, ComicsPageLogic logic) {
    var comicsCount = _currentComics(logic).length;
    return SliverAppbar(
      radius: UiMode.m1(context) ? 0 : 16,
      color: logic.selecting
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      leading: logic.selecting
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => logic.exitSelectMode(),
            )
          : null,
      title: logic.selecting
          ? Text("已选择 @num 个项目".tlParams({"num": logic.selectedCount.toString()}))
          : Text(title!),
      actions: [
        if (tailing != null && !logic.selecting) tailing!,
        if (comicsCount > 0)
          if (logic.selecting)
            IconButton(
              tooltip: "全选".tl,
              icon: Icon(logic.selectedCount == comicsCount
                  ? Icons.deselect
                  : Icons.select_all),
              onPressed: () {
                if (logic.selectedCount == comicsCount) {
                  logic.selected.clear();
                } else {
                  logic.selectAll(comicsCount);
                }
                logic.update();
              },
            )
          else
            IconButton(
              tooltip: "多选".tl,
              icon: const Icon(Icons.checklist),
              onPressed: () => logic.enterSelectMode(),
            ),
      ],
    );
  }

  /// 多选模式下给每个漫画块添加选择层
  Widget _buildItemWithSelection(
      BuildContext context, T item, int index, ComicsPageLogic logic) {
    var tile = buildItem(context, item);
    if (!logic.selecting) return tile;
    final isSelected = logic.selected.contains(index);
    return Stack(
      fit: StackFit.expand,
      children: [
        tile,
        Positioned.fill(
          child: Material(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            child: InkWell(
              onTap: () => logic.toggleSelect(index),
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 多选模式下在底部附加操作栏
  Widget _withSelectionBar(
      BuildContext context, ComicsPageLogic logic, Widget child) {
    if (!logic.selecting) return child;
    return Column(
      children: [
        Expanded(child: child),
        _buildSelectionBar(context, logic),
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context, ComicsPageLogic logic) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: logic.selectedCount == 0
                    ? null
                    : () => _batchFavorite(context, logic),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text("收藏".tl),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: logic.selectedCount == 0
                    ? null
                    : () => _batchDownload(context, logic),
                icon: const Icon(Icons.download_outlined),
                label: Text("下载".tl),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => logic.exitSelectMode(),
                child: Text("完成".tl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<T> _selectedComics(ComicsPageLogic logic) {
    var comics = _currentComics(logic);
    return [
      for (var i in logic.selected)
        if (i >= 0 && i < comics.length) comics[i],
    ];
  }

  /// 批量加入本地收藏
  Future<void> _batchFavorite(BuildContext context, ComicsPageLogic logic) async {
    var selected = _selectedComics(logic);
    if (selected.isEmpty) return;
    var items = selected.map((comic) => FavoriteItem.fromBaseComic(comic)).toList();

    var folderNames = LocalFavoritesManager().folderNames;
    var folder = appdata.settings[51];
    if (folder.isEmpty || !folderNames.contains(folder)) {
      folder = folderNames.isNotEmpty ? folderNames.first : "1";
    }
    var initialFolderIndex = folderNames.indexOf(folder);
    await showDialog(
      context: context,
      builder: (dialogContext) {
        String? newFolder = folder;
        return SimpleDialog(
          title: Text("收藏到收藏夹".tl),
          children: [
            ListTile(
              title: Text("收藏夹".tl),
              trailing: Select(
                outline: true,
                width: 180,
                values: folderNames,
                initialValue: initialFolderIndex == -1 ? null : initialFolderIndex,
                onChange: (i) => newFolder = folderNames[i],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: FilledButton(
                child: Text("确认".tl),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  for (var f in items) {
                    LocalFavoritesManager().addComic(newFolder!, f);
                  }
                  logic.exitSelectMode();
                  showToast(message: "已收藏".tl);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// 批量下载
  Future<void> _batchDownload(BuildContext context, ComicsPageLogic logic) async {
    var selected = _selectedComics(logic);
    if (selected.isEmpty) return;
    var source = ComicSource.find(sourceKey);
    if (source == null || source.loadComicInfo == null) {
      showToast(message: "该漫画源不支持下载".tl);
      return;
    }
    var controller = showLoadingDialog(
      context,
      message: "获取漫画信息".tl,
      allowCancel: false,
    );
    int success = 0;
    int failed = 0;
    try {
      for (var comic in selected) {
        var res = await source.loadComicInfo!(comic.id);
        if (res.success) {
          var data = res.data;
          List<int> eps;
          if (data.chapters == null || data.chapters!.isEmpty) {
            eps = [0];
          } else {
            eps = List<int>.generate(data.chapters!.length, (i) => i);
          }
          downloadManager.addCustomDownload(data, eps);
          success++;
        } else {
          failed++;
        }
      }
    } finally {
      controller.close();
    }
    if (failed > 0) {
      showToast(
          message: "已添加 @num 个下载任务, @failed 个失败".tlParams({
        "num": success.toString(),
        "failed": failed.toString(),
      }));
    } else {
      showToast(
          message: "已添加 @num 个下载任务".tlParams({"num": success.toString()}));
    }
    logic.exitSelectMode();
  }

  Widget buildPageSelector(BuildContext context, ComicsPageLogic logic) {
    return SliverToBoxAdapter(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: SizedBox(
            width: 300,
            height: 42,
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                ),
                FilledButton.tonal(
                    onPressed: () => prevPage(logic), child: Text("上一页".tl)),
                const Spacer(),
                ActionChip(
                  label: Text(
                      "${"页面".tl}: ${logic.current}/${logic.maxPage?.toString() ?? "?"}"),
                  onPressed: () async {
                    selectPage(logic);
                  },
                  elevation: 1,
                  side: BorderSide.none,
                ),
                const Spacer(),
                FilledButton.tonal(
                    onPressed: () => nextPage(logic), child: Text("下一页".tl)),
                const SizedBox(
                  width: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPageSelectorRight(BuildContext context, ComicsPageLogic logic) {
    return Align(
        alignment: Alignment.centerRight,
        child: AnimatedSlide(
          offset: logic.showFloatingButton
              ? const Offset(0, 0)
              : const Offset(1.5, 0),
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 3,
            child: SizedBox(
              height: 156,
              width: 58,
              child: Column(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16)),
                      onTap: () {
                        prevPage(logic);
                      },
                      child: const SizedBox.expand(
                        child: Center(
                          child: Icon(Icons.keyboard_arrow_left),
                        ),
                      ),
                    ),
                  ),
                  const Divider(
                    height: 1,
                  ),
                  Expanded(
                      child: InkWell(
                    onTap: () {
                      selectPage(logic);
                    },
                    child: SizedBox.expand(
                      child: Center(
                        child: Text(
                            "${logic.current}/${logic.maxPage?.toString() ?? "?"}"),
                      ),
                    ),
                  )),
                  const Divider(
                    height: 1,
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16)),
                      onTap: () {
                        nextPage(logic);
                      },
                      child: const SizedBox.expand(
                        child: Center(
                          child: Icon(Icons.keyboard_arrow_right),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  void nextPage(ComicsPageLogic logic) {
    if (logic.current == logic.maxPage || logic.current == 0) {
      showToast(message: "已经是最后一页了".tl);
    } else {
      logic.current++;
      logic.update();
    }
  }

  void prevPage(ComicsPageLogic logic) {
    if (logic.current == 1 || logic.current == 0) {
      showToast(message: "已经是第一页了".tl);
    } else {
      logic.current--;
      logic.update();
    }
  }

  void selectPage(ComicsPageLogic logic) async {
    String res = "";
    await showDialog(
        context: App.globalContext!,
        builder: (dialogContext) {
          var controller = TextEditingController();
          return SimpleDialog(
            title: const Text("切换页面"),
            children: [
              const SizedBox(
                width: 300,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: TextField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: "页码".tl,
                    suffixText:
                        "${"输入范围: ".tl}1-${logic.maxPage?.toString() ?? "?"}",
                  ),
                  controller: controller,
                  onSubmitted: (s) {
                    res = s;
                    App.globalBack();
                  },
                ),
              ),
              Center(
                child: FilledButton(
                  child: Text("提交".tl),
                  onPressed: () {
                    res = controller.text;
                    App.globalBack();
                  },
                ),
              )
            ],
          );
        });
    if (res.isNum) {
      int i = int.parse(res);
      if (logic.maxPage == null || (i > 0 && i <= logic.maxPage!)) {
        logic.current = i;
        logic.update();
        return;
      }
    }
    if (res != "") {
      showToast(message: "输入的数字不正确".tl);
    }
  }

  Widget buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 12),
          Text("无匹配结果".tl,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget buildItem(BuildContext context, T item) {
    return buildComicTile(context, item, sourceKey, addonMenuOptions: addonMenuOptions);
  }
}

class SliverGridComicsController extends StateController {}

class SliverGridComics extends StatelessWidget {
  const SliverGridComics({
    super.key,
    required this.comics,
    required this.sourceKey,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final String sourceKey;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<SliverGridComicsController>(
      init: SliverGridComicsController(),
      builder: (controller) {
        List<BaseComic> comics = [];
        if (appdata.appSettings.fullyHideBlockedWorks) {
          for (var comic in this.comics) {
            if (isBlocked(comic) == null) {
              comics.add(comic);
            }
          }
        } else {
          comics = this.comics;
        }
        return _SliverGridComics(
          comics: comics,
          sourceKey: sourceKey,
          onLastItemBuild: onLastItemBuild,
        );
      },
    );
  }
}

class _SliverGridComics extends StatelessWidget {
  const _SliverGridComics({
    required this.comics,
    required this.sourceKey,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final String sourceKey;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          if (index == comics.length - 1) {
            onLastItemBuild?.call();
          }
          return buildComicTile(context, comics[index], sourceKey);
        },
        childCount: comics.length,
      ),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }
}