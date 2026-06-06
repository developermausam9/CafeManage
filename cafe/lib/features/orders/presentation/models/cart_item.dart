import '../../../menu/data/models/product_model.dart';

class CartItem {
  final ProductModel product;
  double quantity;
  String? note;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.note,
  });

  double get totalPrice => product.sellingPrice * quantity;
}
