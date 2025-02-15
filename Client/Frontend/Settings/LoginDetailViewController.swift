/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Storage
import Shared
import SwiftKeychainWrapper

enum InfoItem: Int {
    case websiteItem = 0
    case usernameItem
    case passwordItem
    case lastModifiedSeparator
    case deleteItem

    var indexPath: IndexPath {
        return IndexPath(row: rawValue, section: 0)
    }
}

private struct LoginDetailUX {
    static let InfoRowHeight: CGFloat = 58
    static let DeleteRowHeight: CGFloat = 44
    static let SeparatorHeight: CGFloat = 84
}

fileprivate class CenteredDetailCell: ThemedTableViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        var f = detailTextLabel?.frame ?? CGRect()
        f.center = frame.center
        detailTextLabel?.frame = f
    }
}

class LoginDetailViewController: SensitiveViewController {
    fileprivate let profile: Profile
    fileprivate let tableView = UITableView()
    fileprivate weak var websiteField: UITextField?
    fileprivate weak var usernameField: UITextField?
    fileprivate weak var passwordField: UITextField?
    // Used to temporarily store a reference to the cell the user is showing the menu controller for
    fileprivate var menuControllerCell: LoginTableViewCell?
    fileprivate var deleteAlert: UIAlertController?
    weak var settingsDelegate: SettingsDelegate?

    fileprivate var login: LoginRecord {
        didSet {
            tableView.reloadData()
        }
    }

    fileprivate var isEditingFieldData: Bool = false {
        didSet {
            if isEditingFieldData != oldValue {
                tableView.reloadData()
            }
        }
    }

    init(profile: Profile, login: LoginRecord) {
        self.login = login
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(dismissAlertController), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(self.view)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        tableView.separatorColor = UIColor.theme.tableView.separator
        tableView.backgroundColor = UIColor.theme.tableView.headerBackground
        tableView.accessibilityIdentifier = "Login Detail List"
        tableView.delegate = self
        tableView.dataSource = self

        // Add empty footer view to prevent seperators from being drawn past the last item.
        tableView.tableFooterView = UIView()

        // Normally UITableViewControllers handle responding to content inset changes from keyboard events when editing
        // but since we don't use the tableView's editing flag for editing we handle this ourselves.
        KeyboardHelper.defaultHelper.addDelegate(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The following hacks are to prevent the default cell seperators from displaying. We want to
        // hide the default seperator for the website/last modified cells since the last modified cell
        // draws its own separators. The last item in the list draws its seperator full width.

        // Prevent seperators from showing by pushing them off screen by the width of the cell
        let itemsToHideSeperators: [InfoItem] = [.passwordItem, .lastModifiedSeparator]
        itemsToHideSeperators.forEach { item in
            let cell = tableView.cellForRow(at: IndexPath(row: item.rawValue, section: 0))
            cell?.separatorInset = UIEdgeInsets(top: 0, left: cell?.bounds.width ?? 0, bottom: 0, right: 0)
        }

        // Rows to display full width seperator
        let itemsToShowFullWidthSeperator: [InfoItem] = [.deleteItem]
        itemsToShowFullWidthSeperator.forEach { item in
            let cell = tableView.cellForRow(at: IndexPath(row: item.rawValue, section: 0))
            cell?.separatorInset = .zero
            cell?.layoutMargins = .zero
            cell?.preservesSuperviewLayoutMargins = false
        }
    }
}

// MARK: - UITableViewDataSource
extension LoginDetailViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch InfoItem(rawValue: indexPath.row)! {
        case .usernameItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = NSLocalizedString("Username", tableName: "LoginManager", comment: "Label displayed above the username row in Login Detail View.")
            loginCell.descriptionLabel.text = login.username
            loginCell.descriptionLabel.keyboardType = .emailAddress
            loginCell.descriptionLabel.returnKeyType = .next
            loginCell.isEditingFieldData = isEditingFieldData
            usernameField = loginCell.descriptionLabel
            usernameField?.accessibilityIdentifier = "usernameField"
            return loginCell

        case .passwordItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = NSLocalizedString("Password", tableName: "LoginManager", comment: "Label displayed above the password row in Login Detail View.")
            loginCell.descriptionLabel.text = login.password
            loginCell.descriptionLabel.returnKeyType = .default
            loginCell.displayDescriptionAsPassword = true
            loginCell.isEditingFieldData = isEditingFieldData
            passwordField = loginCell.descriptionLabel
            passwordField?.accessibilityIdentifier = "passwordField"
            return loginCell

        case .websiteItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = NSLocalizedString("Website", tableName: "LoginManager", comment: "Label displayed above the website row in Login Detail View.")
            loginCell.descriptionLabel.text = login.hostname
            websiteField = loginCell.descriptionLabel
            websiteField?.accessibilityIdentifier = "websiteField"
            loginCell.isEditingFieldData = false
            if isEditingFieldData {
                loginCell.contentView.alpha = 0.5
            }
            return loginCell

        case .lastModifiedSeparator:
            let cell = CenteredDetailCell(style: .subtitle, reuseIdentifier: nil)
            let created = NSLocalizedString("Created %@", tableName: "LoginManager", comment: "Label describing when the current login was created with the timestamp as the parameter.")
            let lastModified = NSLocalizedString("Modified %@", tableName: "LoginManager", comment: "Label describing when the current login was last modified with the timestamp as the parameter.")

            let lastModifiedFormatted = String(format: lastModified, Date.fromTimestamp(UInt64(login.timePasswordChanged)).toRelativeTimeString(dateStyle: .medium))
            let createdFormatted = String(format: created, Date.fromTimestamp(UInt64(login.timeCreated)).toRelativeTimeString(dateStyle: .medium, timeStyle: .none))
            // Setting only the detail text produces smaller text as desired, and it is centered.
            cell.detailTextLabel?.text = createdFormatted + "\n" + lastModifiedFormatted
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.textAlignment = .center
            cell.backgroundColor = view.backgroundColor
            return cell

        case .deleteItem:
            let deleteCell = cell(forIndexPath: indexPath)
            deleteCell.textLabel?.text = NSLocalizedString("Delete", tableName: "LoginManager", comment: "Label for the button used to delete the current login.")
            deleteCell.textLabel?.textAlignment = .center
            deleteCell.textLabel?.textColor = UIColor.theme.general.destructiveRed
            deleteCell.accessibilityTraits = UIAccessibilityTraits.button
            deleteCell.backgroundColor = UIColor.theme.tableView.rowBackground
            return deleteCell
        }
    }

    fileprivate func cell(forIndexPath indexPath: IndexPath) -> LoginTableViewCell {
        let loginCell = LoginTableViewCell()
        loginCell.selectionStyle = .none
        loginCell.delegate = self
        return loginCell
    }

    fileprivate func wrapFooter(_ footer: UITableViewHeaderFooterView, withCellFromTableView tableView: UITableView, atIndexPath indexPath: IndexPath) -> UITableViewCell {
        let cell = self.cell(forIndexPath: indexPath)
        cell.selectionStyle = .none
        cell.addSubview(footer)
        footer.snp.makeConstraints { make in
            make.edges.equalTo(cell)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 5
    }
}

// MARK: - UITableViewDelegate
extension LoginDetailViewController: UITableViewDelegate {
    private func showMenuOnSingleTap(forIndexPath indexPath: IndexPath) {
        guard let item = InfoItem(rawValue: indexPath.row) else { return }
        if ![InfoItem.passwordItem, InfoItem.websiteItem, InfoItem.usernameItem].contains(item) {
            return
        }

        guard let cell = tableView.cellForRow(at: indexPath) as? LoginTableViewCell else { return }

        cell.becomeFirstResponder()

        let menu = UIMenuController.shared
        menu.setTargetRect(cell.frame, in: self.tableView)
        menu.setMenuVisible(true, animated: true)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath == InfoItem.deleteItem.indexPath {
            deleteLogin()
        } else if !isEditingFieldData {
            showMenuOnSingleTap(forIndexPath: indexPath)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch InfoItem(rawValue: indexPath.row)! {
        case .usernameItem, .passwordItem, .websiteItem:
            return LoginDetailUX.InfoRowHeight
        case .lastModifiedSeparator:
            return LoginDetailUX.SeparatorHeight
        case .deleteItem:
            return LoginDetailUX.DeleteRowHeight
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension LoginDetailViewController: KeyboardHelperDelegate {

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - Selectors
extension LoginDetailViewController {

    @objc func dismissAlertController() {
        self.deleteAlert?.dismiss(animated: false, completion: nil)
    }

    func deleteLogin() {
        profile.logins.hasSyncedLogins().uponQueue(.main) { yes in
            self.deleteAlert = UIAlertController.deleteLoginAlertWithDeleteCallback({ [unowned self] _ in
                self.profile.logins.delete(id: self.login.id).uponQueue(.main) { _ in
                    _ = self.navigationController?.popViewController(animated: true)
                }
            }, hasSyncedLogins: yes.successValue ?? true)

            self.present(self.deleteAlert!, animated: true, completion: nil)
        }
    }

    func onProfileDidFinishSyncing() {
        // Reload details after syncing.
        profile.logins.get(id: login.id).uponQueue(.main) { result in
            if let successValue = result.successValue, let syncedLogin = successValue {
                self.login = syncedLogin
            }
        }
    }

    @objc func edit() {
        isEditingFieldData = true
        guard let cell = tableView.cellForRow(at: InfoItem.usernameItem.indexPath) as? LoginTableViewCell else { return }
        cell.descriptionLabel.becomeFirstResponder()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneEditing))
    }

    @objc func doneEditing() {
        isEditingFieldData = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(edit))

        defer {
            // Required to get UI to reload with changed state
            tableView.reloadData()
        }

        // Only update if user made changes
        guard let username = usernameField?.text, let password = passwordField?.text else { return }
        guard username != login.username || password != login.password else { return }

        // Keep a copy of the old data in case we fail and need to revert back
        let oldInfo = (pass: login.password, user: login.username)
        login.password = password
        login.username = username

        if login.isValid.isSuccess {
            _ = profile.logins.update(login: login)
        } else {
            login.password = oldInfo.pass
            login.username = oldInfo.user
        }
    }
}

// MARK: - Cell Delegate
extension LoginDetailViewController: LoginTableViewCellDelegate {

    fileprivate func cellForItem(_ item: InfoItem) -> LoginTableViewCell? {
        return tableView.cellForRow(at: item.indexPath) as? LoginTableViewCell
    }

    func didSelectOpenAndFillForCell(_ cell: LoginTableViewCell) {
        guard let url = (self.login.formSubmitUrl?.asURL ?? self.login.hostname.asURL) else {
            return
        }

        navigationController?.dismiss(animated: true, completion: {
            self.settingsDelegate?.settingsOpenURLInNewTab(url)
        })
    }

    func shouldReturnAfterEditingDescription(_ cell: LoginTableViewCell) -> Bool {
        let usernameCell = cellForItem(.usernameItem)
        let passwordCell = cellForItem(.passwordItem)

        if cell == usernameCell {
            passwordCell?.descriptionLabel.becomeFirstResponder()
        }

        return false
    }

    func infoItemForCell(_ cell: LoginTableViewCell) -> InfoItem? {
        if let index = tableView.indexPath(for: cell),
            let item = InfoItem(rawValue: index.row) {
            return item
        }
        return nil
    }
}
