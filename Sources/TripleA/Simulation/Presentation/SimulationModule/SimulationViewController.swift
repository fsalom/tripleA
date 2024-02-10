//
//  SimulationViewController.swift
//  
//
//  Created by Pablo Ceacero on 9/1/24.
//

import UIKit

public class SimulationViewController: UIViewController {

    // MARK: - Dependencies
    public struct Dependencies {
        let viewModel: SimulationViewModel
        let targetVC: UIViewController
        let targetName: String
    }

    // MARK: - Properties

    var viewModel: SimulationViewModel!
    var targetVC: UIViewController!
    var targetName: String!

    // MARK: - Views

    var headerView: SimulationHeaderView!
    var tableView: UITableView!

    // MARK: - Life Cycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }
}

// MARK: - Layout

fileprivate extension SimulationViewController {

    func setupView() {
        setupTableView()
        setupHeaderView()
    }

    func setupHeaderView() {
        headerView = SimulationHeaderView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        headerView.setup(with: SimulationHeaderView.Dependencies(screenName: targetName))
        setupHeaderViewConstraints()
    }

    func setupTableView() {
        tableView = UITableView(frame: .zero,
                                style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(SimulationTableCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        tableView.register(SimulationSectionHeaderView.self,
                           forHeaderFooterViewReuseIdentifier: Constants.headerIdentifier)
        tableView.contentInset.top = 350
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        setupTableViewConstraints()
    }

    func setupTableViewConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func setupHeaderViewConstraints() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 350)
        ])
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension SimulationViewController: UITableViewDataSource, UITableViewDelegate {

    public func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.getEndpoints().count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.responsesForEndpoint(endpointId: viewModel.getEndpoints()[section].id).count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier,
                                                 for: indexPath) as! SimulationTableCell
        let endpointId = viewModel.getEndpoints()[indexPath.section].id
        let response = viewModel.responsesForEndpoint(endpointId: endpointId)[indexPath.row]
        let isResponseSelected = viewModel.isResponseSimulationEnabled(responseId: response.id)
        cell.setup(dependencies: SimulationTableCell.Dependencies(responseName: response.displayName,
                                                                  endpointId: endpointId,
                                                                  responseId: response.id,
                                                                  isResponseSelected: isResponseSelected))
        return cell
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Constants.headerIdentifier) as! SimulationSectionHeaderView
        header.delegate = self
        let simulationEndpoint = viewModel.getEndpoints()[section]
        let isEndpointSimulationEnabled = viewModel.isEndpointSimulationEnabled(endpointId: simulationEndpoint.id)
        header.setup(with: SimulationSectionHeaderView.Dependencies(displayName: simulationEndpoint.displayName,
                                                                    endpointId: simulationEndpoint.id,
                                                                    isEndpointSimulationEnabled: isEndpointSimulationEnabled))
        return header
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        Constants.sectionHeaderHeight
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let endpointId = viewModel.getEndpoints()[indexPath.section].id
        let responseId = viewModel.responsesForEndpoint(endpointId: endpointId)[indexPath.row].id
        viewModel.updateResponseSimulationEnabled(enabled: true, for: responseId, from: endpointId)
        tableView.reloadSections([indexPath.section], with: .automatic)
    }
}

// MARK: - SimulationHeaderViewProtocol

extension SimulationViewController: SimulationSectionHeaderViewProtocol {
    func didEnableEndpoint(_ endpointId: SimulationEndpoint.ID, enabled: Bool) {
        viewModel.updateEndpointSimulationEnabled(for: endpointId, enabled: enabled)
        guard let index = viewModel.getEndpoints().firstIndex(where: { $0.id == endpointId }) else { return }
        tableView.reloadSections([index], with: .automatic)
    }
}

extension SimulationViewController {
    enum Constants {
        static let cellIdentifier = "SimulationTableCell"
        static let headerIdentifier = "SimulationHeaderCell"
        static let sectionHeaderHeight = 60.0
    }
}
