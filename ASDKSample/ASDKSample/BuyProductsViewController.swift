//
//  BuyProductsViewController.swift
//  ASDKSample
//
//  Copyright (c) 2020 Tinkoff Bank
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import TinkoffASDKCore
import TinkoffASDKUI

class BuyProductsViewController: UIViewController {
	
	enum TableViewCellType {
		case products
		/// открыть экран оплаты и перейти к оплате
		case pay
		/// оплатить с карты - выбрать карту из списка и сделать этот платеж родительским
		case payAndSaveAsParent
		/// оплатить
		case payRequrent
		/// оплатить с помощью `ApplePay`
		case payApplePay
		/// оплатить с помощью `Системы Быстрых Платежей`
		/// сгенерировать QR-код для оплаты
		case paySbpQrCode
		/// оплатить с помощью `Системы Быстрых Платежей`
		/// сгенерировать url для оплаты
		case paySbpUrl
	}
	
	private var tableViewCells: [TableViewCellType] = []
	
	var products: [Product] = []
	var sdk: AcquiringUISDK!
	var customerKey: String!
	var customerEmail: String = "customer@email.com"
	weak var scaner: AcquiringScanerProtocol?

	lazy var paymentApplePayConfiguration = AcquiringUISDK.ApplePayConfiguration()
	var paymentCardId: PaymentCard?
	var paymentCardParentPaymentId: PaymentCard?
	
	private var rebuidIdCards: [PaymentCard]?
	
	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var buttonAddToCart: UIBarButtonItem!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		title = NSLocalizedString("title.paymentSource", comment: "Источник оплаты")
		
		tableView.registerCells(types: [ButtonTableViewCell.self])
		tableView.delegate = self
		tableView.dataSource = self
				
		sdk.setupCardListDataProvider(for: customerKey, statusListener: self)
		sdk.cardListReloadData()
		sdk.addCardNeedSetCheckTypeHandler = {
			return AppSetting.shared.addCardChekType
		}
		
		if products.count > 1 {
			buttonAddToCart.isEnabled = false
			buttonAddToCart.title = nil
		}

	}
	
	@IBAction func addToCart(_ sender: Any) {
		if let product = products.first {
			CartDataProvider.shared.addProduct(product)
		}
	}
	
	func updateTableViewCells() {
		tableViewCells = [.products,
						  .pay,
						  .payAndSaveAsParent,
						  .payRequrent]
		
		tableViewCells.append(.payApplePay)
		tableViewCells.append(.paySbpQrCode)
		tableViewCells.append(.paySbpUrl)
	}
	
	private func selectRebuildCard() {
		if let cards: [PaymentCard] = rebuidIdCards, cards.isEmpty == false, let viewController = UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "SelectRebuildCardViewController") as? SelectRebuildCardViewController {
			viewController.cards = cards
			viewController.onSelectCard = { card in
				self.paymentCardParentPaymentId = card
				if let index = self.tableViewCells.firstIndex(of: .payRequrent) {
					self.tableView.beginUpdates()
						self.tableView.reloadSections(IndexSet.init(integer: index), with: .fade)
					self.tableView.endUpdates()
				}
			}
			
			present(UINavigationController.init(rootViewController: viewController), animated: true, completion: nil)
		}
	}
	
	private func productsAmount() -> Double {
		var amount: Double = 0

		products.forEach { (product) in
			amount += product.price.doubleValue
		}
		
		return amount
	}
	
	private func createPaymentData() -> PaymentInitData {
		let amount = productsAmount()
		var paymentData = PaymentInitData.init(amount: NSDecimalNumber.init(value: amount), orderId: Int64(arc4random()), customerKey: customerKey)
		var receiptItems: [Item] = []
		products.forEach { (product) in
			receiptItems.append(Item.init(amount: product.price, price: product.price, name: product.name, tax: .vat10))
		}
		
		paymentData.receipt = Receipt.init(shopCode: nil,
										   email: customerEmail,
										   taxation: .osn,
										   phone: nil,
										   items: receiptItems,
										   agentData: nil,
										   supplierInfo: nil,
										   customer: nil,
										   customerInn: nil)
		
		return paymentData
	}
	
	private func acquiringViewConfigration() -> AcquiringViewConfigration {
		let viewConfigration = AcquiringViewConfigration.init()
		viewConfigration.scaner = scaner
		
		viewConfigration.fields = []
		// InfoFields.amount
		let title = NSAttributedString.init(string: NSLocalizedString("title.paymeny", comment: "Оплата"), attributes: [.font: UIFont.boldSystemFont(ofSize: 22)])
		let amountString = Utils.formatAmount(NSDecimalNumber.init(floatLiteral: productsAmount()))
		let amountTitle = NSAttributedString.init(string: "\(NSLocalizedString("text.totalAmount", comment: "на сумму")) \(amountString)", attributes: [.font : UIFont.systemFont(ofSize: 17)])
		// fields.append
		viewConfigration.fields.append(AcquiringViewConfigration.InfoFields.amount(title: title, amount: amountTitle))
		
		// InfoFields.detail
		let productsDetatils = NSMutableAttributedString.init()
		productsDetatils.append(NSAttributedString.init(string: "Книги\n", attributes: [.font : UIFont.systemFont(ofSize: 17)]))
		
		let productsDetails = products.map { (product) -> String in
			return product.name
		}.joined(separator: ", ")
		
		productsDetatils.append(NSAttributedString.init(string: productsDetails, attributes: [.font : UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor(red: 0.573, green: 0.6, blue: 0.635, alpha: 1)]))
		// fields.append
		viewConfigration.fields.append(AcquiringViewConfigration.InfoFields.detail(title: productsDetatils))
		
		if AppSetting.shared.showEmailField {
			viewConfigration.fields.append(AcquiringViewConfigration.InfoFields.email(value: nil, placeholder: NSLocalizedString("plaseholder.email", comment: "Отправить квитанцию по адресу")))
		}
		
		// fields.append InfoFields.buttonPaySPB
		if AppSetting.shared.paySBP {
			viewConfigration.fields.append(AcquiringViewConfigration.InfoFields.buttonPaySPB)
		}

		viewConfigration.viewTitle = NSLocalizedString("title.pay", comment: "Оплата")
		viewConfigration.localizableInfo = AcquiringViewConfigration.LocalizableInfo.init(lang: AppSetting.shared.languageId)
		
		return viewConfigration
	}
	
	private func responseReviewing(_ response: Result<PaymentStatusResponse, Error>) {
		switch response {
			case .success(let result):
				var message = "Покупка на сумму \(Utils.formatAmount(result.amount))"
				if result.status == .cancelled {
					message.append(" отменена")
				} else {
					message.append(" прошла успешно.\npaymentId = \(result.paymentId)")
				}
				
				let alertView = UIAlertController.init(title: "Tinkoff Acquaring", message: message, preferredStyle: .alert)
				alertView.addAction(UIAlertAction.init(title: "ОК", style: .default, handler: nil))
				present(alertView, animated: true, completion: nil)
			case .failure(let error):
				let alertView = UIAlertController.init(title: "Tinkoff Acquaring", message: error.localizedDescription, preferredStyle: .alert)
				alertView.addAction(UIAlertAction.init(title: "ОК", style: .default, handler: nil))
				present(alertView, animated: true, completion: nil)
		}
	}
	
	private func presentPaymentView(paymentData: PaymentInitData, viewConfigration: AcquiringViewConfigration) {
		sdk.presentPaymentView(on: self, paymentData: paymentData, configuration: viewConfigration) { [weak self] (response) in
			self?.responseReviewing(response)
		}
	}
	
	func pay() {
		presentPaymentView(paymentData: createPaymentData(), viewConfigration: acquiringViewConfigration())
	}
	
	func payByApplePay() {
		sdk.presentPaymentApplePay(on: self,
								   paymentData: createPaymentData(),
								   viewConfiguration: AcquiringViewConfigration.init(),
								   paymentConfiguration: paymentApplePayConfiguration) { [weak self] (response) in
									self?.responseReviewing(response)
		}
	}
	
	func payAndSaveAsParent() {
		var paymentData = createPaymentData()
		paymentData.savingAsParentPayment = true
		
		presentPaymentView(paymentData: paymentData, viewConfigration: acquiringViewConfigration())
	}
	
	func charge(_ complete: @escaping (()-> Void)) {
		if let parentPaymentId = paymentCardParentPaymentId?.parentPaymentId {
			sdk.presentPaymentView(on: self, paymentData: createPaymentData(), parentPatmentId: parentPaymentId, configuration: acquiringViewConfigration()) { [weak self] (response) in
				complete()
				self?.responseReviewing(response)
			}
		}
	}
	
	func generateSbpQrImage() {
		sdk.presentPaymentSbpQrImage(on: self, paymentData: createPaymentData(), configuration: acquiringViewConfigration()) { [weak self] (response) in
			self?.responseReviewing(response)
		}
	}
	
	func generateSbpUrl() {
		sdk.presentPaymentSbpUrl(on: self, paymentData: createPaymentData(), configuration: acquiringViewConfigration()) { [weak self] (response) in
			self?.responseReviewing(response)
		}
	}
	
}

extension BuyProductsViewController: CardListDataSourceStatusListener {
	
	// MARK: CardListDataSourceStatusListener
	
	func cardsListUpdated(_ status: FetchStatus<[PaymentCard]>) {
		switch status {
			case .object(let cards):
				if paymentCardId == nil {
					paymentCardId = cards.first
				}
				
				rebuidIdCards = cards.filter { (card) -> Bool in
					return card.parentPaymentId != nil
				}
				
				if paymentCardParentPaymentId == nil {
					paymentCardParentPaymentId = cards.last(where: { (card) -> Bool in
						return card.parentPaymentId != nil
					})
				}
			
			default:
				break
		}
		
		updateTableViewCells()
		tableView.reloadData()
	}
	
}

extension BuyProductsViewController: UITableViewDataSource {
	
	// MARK: UITableViewDataSource
	
	private func yellowButtonColor() -> UIColor {
		return UIColor(red: 1, green: 0.867, blue: 0.176, alpha: 1)
	}
	
	func numberOfSections(in tableView: UITableView) -> Int {
		return tableViewCells.count
	}
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		var result = 1

		switch tableViewCells[section] {
			case .products:
				result = products.count
			
			case .payRequrent:
				if rebuidIdCards?.count ?? 0 > 0 {
					result = 2
				}
			
			default:
				result = 1
		}
		
		return result
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch tableViewCells[indexPath.section] {
			case .products:
				let cell = tableView.defaultCell()
				let product = products[indexPath.row]
				cell.textLabel?.text = product.name
				cell.detailTextLabel?.text = Utils.formatAmount(product.price)
				return cell
				
			case .pay:
				if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
					cell.button.setTitle(NSLocalizedString("button.pay", comment: "Оплатить"), for: .normal)
					cell.button.isEnabled = true
					cell.button.backgroundColor = yellowButtonColor()
					cell.button.setImage(nil, for: .normal)
					cell.onButtonTouch = { [weak self] in
						self?.pay()
					}
					
					return cell
				}

			case .payAndSaveAsParent:
				if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
					cell.button.setTitle(NSLocalizedString("button.pay", comment: "Оплатить"), for: .normal)
					cell.button.isEnabled = true
					cell.button.backgroundColor = yellowButtonColor()
					cell.button.setImage(nil, for: .normal)
					cell.onButtonTouch = { [weak self] in
						self?.payAndSaveAsParent()
					}
					
					return cell
				}
			
			case .payRequrent:
				if indexPath.row == 0 {
					if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
						cell.button.setTitle(NSLocalizedString("button.paymentTryAgain", comment: "Повторить платеж"), for: .normal)
						cell.button.backgroundColor = yellowButtonColor()
						cell.button.setImage(nil, for: .normal)
						if let card = paymentCardParentPaymentId {
							cell.button.isEnabled = (card.parentPaymentId != nil)
						} else {
							cell.button.isEnabled = false
						}
						
						cell.onButtonTouch = { [weak self, weak cell] in
							cell?.activityIndicator.startAnimating()
							cell?.button.isEnabled = false
							self?.charge {
								cell?.activityIndicator.stopAnimating()
								cell?.button.isEnabled = true
							}
						}
						
						return cell
					}
				} else {
					let cell = tableView.defaultCell()
					cell.accessoryType = .disclosureIndicator
					cell.textLabel?.text = NSLocalizedString("button.selectAnotherCard", comment: "выбрать другую карту")
					cell.detailTextLabel?.text = nil
					return cell
				}
			
			case .payApplePay:
				if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
					cell.button.setTitle(nil, for: .normal)
					cell.button.backgroundColor = .clear
					cell.button.setImage(UIImage.init(named: "buttonApplePay"), for: .normal)
					cell.button.isEnabled = sdk.canMakePaymentsApplePay(with: paymentApplePayConfiguration)
										
					cell.onButtonTouch = { [weak self] in
						self?.payByApplePay()
					}
					
					return cell
				}

			case .paySbpQrCode:
				if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
					cell.button.setTitle(nil, for: .normal)
					cell.button.backgroundColor = .clear
					cell.button.isEnabled = sdk.canMakePaymentsSBP()
					cell.button.setImage(UIImage.init(named: "logo_sbp"), for: .normal)
					cell.onButtonTouch = { [weak self] in
						self?.generateSbpQrImage()
					}
					
					return cell
			}
			
			case .paySbpUrl:
				if let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.nibName) as? ButtonTableViewCell {
					cell.button.setTitle(nil, for: .normal)
					cell.button.backgroundColor = .clear
					cell.button.isEnabled = sdk.canMakePaymentsSBP()
					cell.button.setImage(UIImage.init(named: "logo_sbp"), for: .normal)
					cell.onButtonTouch = { [weak self] in
						self?.generateSbpUrl()
					}
					
					return cell
				}
		}
		
		return tableView.defaultCell()
	}
	
	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch tableViewCells[section] {
			case .products:
				return NSLocalizedString("title.goods", comment: "Товары")
			
			case .pay:
				return NSLocalizedString("title.paymeny", comment: "Оплатить")
			
			case .payAndSaveAsParent:
				return NSLocalizedString("title.payAndSaveAsParent", comment: "Оплатить, начать регулярный платеж")
			
			case .payRequrent:
				return NSLocalizedString("title.paymentTryAgain", comment: "Повторить платеж")
			
			case .payApplePay:
				return NSLocalizedString("title.payByApplePay", comment: "Оплатить с помощью ApplePay")
			
			case .paySbpUrl, .paySbpQrCode:
				return NSLocalizedString("title.payBySBP", comment: "Оплатить с помощью Системы Быстрых Платежей")
		}
		
	}
	
	func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		switch tableViewCells[section] {
			case .products:
				return "сумма: \(Utils.formatAmount(NSDecimalNumber.init(value: productsAmount())))"
			
			case .pay:
				let cards = sdk.cardListNumberOfCards()
				if cards > 0 {
					return "открыть платежную форму и перейти к оплате товара, доступно \(cards) сохраненных карт"
				}
				
				return "открыть платежную форму и перейти к оплате товара"
			
			case .payAndSaveAsParent:
				let cards = sdk.cardListNumberOfCards()
				if cards > 0 {
					return "открыть платежную форму и перейти к оплате товара. При удачной оплате этот платеж сохраниться как родительский. Доступно \(cards) сохраненных карт"
				}
				
				return "оплатить и сделать этот платеж родительским"
						
			case .payRequrent:
				if let card = paymentCardParentPaymentId, let parentPaymentId = card.parentPaymentId {
					return "оплатить с карты \(card.pan) \(card.expDateFormat() ?? ""), используя родительский платеж \(parentPaymentId)"
				}
				
				return "нет доступных родительских платежей"
			
			case .payApplePay:
				if sdk.canMakePaymentsApplePay(with: paymentApplePayConfiguration) {
					return "оплатить с помощью ApplePay"
				}
				
				return "оплата с помощью ApplePay недоступна"
			
			case .paySbpUrl:
				if sdk.canMakePaymentsSBP() {
					return "сгенерировать url и открыть диалог для выбора приложения для оплаты"
				}
				
				return "оплата недоступна"
			
			case .paySbpQrCode:
				if sdk.canMakePaymentsSBP() {
					return "сгенерировать QR-код для оплаты и показать его на экране, для сканирования и оплаты другим смартфоном"
				}
				
				return "оплата недоступна"
		}
	}
	
}

extension BuyProductsViewController: UITableViewDelegate {
	
	// MARK: UITableViewDelegate
	
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		
		switch tableViewCells[indexPath.section] {
			case .payRequrent:
				selectRebuildCard()
					
			default:
				break

		}
	}
	
	func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
		
	}
	
}