import 'package:flutter/foundation.dart';
import '../../data/models/product_model.dart';
import '../../domain/usecases/get_products_usecase.dart';
import '../../domain/usecases/add_product_usecase.dart';
import '../../domain/usecases/update_product_usecase.dart';
import '../../domain/usecases/delete_product_usecase.dart';

enum ProductState { initial, loading, loaded, error }

class ProductProvider extends ChangeNotifier {
  final GetProductsUseCase getProductsUseCase;
  final AddProductUseCase addProductUseCase;
  final UpdateProductUseCase updateProductUseCase;
  final DeleteProductUseCase deleteProductUseCase;

  ProductState _state = ProductState.initial;
  ProductState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<ProductModel> _products = [];
  List<ProductModel> get products => _products;

  ProductProvider({
    required this.getProductsUseCase,
    required this.addProductUseCase,
    required this.updateProductUseCase,
    required this.deleteProductUseCase,
  });

  Future<void> loadProducts(String cafeId) async {
    _setState(ProductState.loading);
    final result = await getProductsUseCase(GetProductsParams(cafeId));
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _setState(ProductState.error);
      },
      (productList) {
        _products = productList;
        _setState(ProductState.loaded);
      },
    );
  }

  Future<void> addProduct(ProductModel product) async {
    _setState(ProductState.loading);
    final result = await addProductUseCase(AddProductParams(product));
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _setState(ProductState.error);
      },
      (newProduct) {
        _products.add(newProduct);
        _setState(ProductState.loaded);
      },
    );
  }

  Future<void> updateProduct(ProductModel product) async {
    _setState(ProductState.loading);
    final result = await updateProductUseCase(UpdateProductParams(product));
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _setState(ProductState.error);
      },
      (updatedProduct) {
        final index = _products.indexWhere((p) => p.id == updatedProduct.id);
        if (index != -1) {
          _products[index] = updatedProduct;
        }
        _setState(ProductState.loaded);
      },
    );
  }

  Future<void> deleteProduct(String id, String cafeId) async {
    _setState(ProductState.loading);
    final result = await deleteProductUseCase(DeleteProductParams(id: id, cafeId: cafeId));
    
    result.fold(
      (failure) {
        _errorMessage = failure.message;
        _setState(ProductState.error);
      },
      (_) {
        _products.removeWhere((p) => p.id == id);
        _setState(ProductState.loaded);
      },
    );
  }

  /// Locally increments stock for a product after a purchase entry
  void incrementStock(String productId, int qty) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final p = _products[index];
      _products[index] = p.copyWith(stockQuantity: p.stockQuantity + qty);
      notifyListeners();
    }
  }

  void _setState(ProductState newState) {
    _state = newState;
    notifyListeners();
  }
}
