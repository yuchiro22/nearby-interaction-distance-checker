/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that facilitates the primary Nearby-Interaction user experience.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity

class ViewController: UIViewController, NISessionDelegate {

    // MARK: - IBOutlets
    @IBOutlet weak var monkeyLabel: UILabel!
    @IBOutlet weak var centerInformationLabel: UILabel!
    @IBOutlet weak var detailContainer: UIView!
    @IBOutlet weak var detailAzimuthLabel: UILabel!
    @IBOutlet weak var detailDeviceNameLabel: UILabel!
    @IBOutlet weak var detailDistanceLabel: UILabel!
    @IBOutlet weak var detailDownArrow: UIImageView!
    @IBOutlet weak var detailElevationLabel: UILabel!
    @IBOutlet weak var detailLeftArrow: UIImageView!
    @IBOutlet weak var detailRightArrow: UIImageView!
    @IBOutlet weak var detailUpArrow: UIImageView!
    @IBOutlet weak var detailAngleInfoView: UIView!

    // MARK: - Distance and direction state
    let nearbyDistanceThreshold: Float = 0.3 // meters

    enum DistanceDirectionState {
        case closeUpInFOV, notCloseUpInFOV, outOfFOV, unknown
    }
    
    enum SonorState {
        case red, yellow, green, none
    }
    
    // MARK: - Class variables
    var session: NISession?
    var peerDiscoveryToken: NIDiscoveryToken?
    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    let circleLayer = CAShapeLayer()
    let animationGroup = CAAnimationGroup()
    var currentDistanceDirectionState: DistanceDirectionState = .unknown
    var currentSonorState: SonorState = .none {
        didSet {
            updateSonorView()
        }
    }
    var mpc: MPCSession?
    var connectedPeer: MCPeerID?
    var sharedTokenWithPeer = false
    var peerDisplayName: String?

    // MARK: - UI LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        monkeyLabel.alpha = 0.0
        monkeyLabel.text = "🙈"
        centerInformationLabel.alpha = 1.0
        detailContainer.alpha = 0.0
        drawSonor()
        
        // Start the NISessions
        startup()
    }
    
    func drawSonor() {
        let path = UIBezierPath(arcCenter: CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2),
                                radius: 100,
                                startAngle: 0,
                                endAngle: .pi * 2.0,
                                clockwise: true
        )
        
        let endPath =  UIBezierPath(arcCenter: CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2),
                                    radius: view.bounds.width,
                                    startAngle: 0,
                                    endAngle: .pi * 2.0,
                                    clockwise: true
        )
        
        circleLayer.fillColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0).cgColor
        circleLayer.path = path.cgPath
        
        view.layer.addSublayer(circleLayer)
        
        // Animate the Path
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = path.cgPath
        pathAnimation.toValue = endPath.cgPath
        
        // Animate the alpha value
        let alphaAnimation = CABasicAnimation(keyPath: "alpha")
        alphaAnimation.fromValue = 0.8
        alphaAnimation.toValue = 0
        
        // Run Path and Alpha animation simultaneously
        animationGroup.beginTime = 0
        animationGroup.animations = [pathAnimation, alphaAnimation]
        animationGroup.duration = 1.88
        animationGroup.repeatCount = .greatestFiniteMagnitude
        animationGroup.isRemovedOnCompletion = false
        animationGroup.fillMode = CAMediaTimingFillMode.forwards

        // Add the animation to the layer.
        circleLayer.add(animationGroup, forKey: "sonar")
    }
    
    func updateSonorView() {
        switch currentSonorState {
        case .green:
            circleLayer.strokeColor = #colorLiteral(red: 0.3411764801, green: 0.6235294342, blue: 0.1686274558, alpha: 1).cgColor
            animationGroup.duration = 1.88
        case .yellow:
            circleLayer.strokeColor = #colorLiteral(red: 0.9529411793, green: 0.6862745285, blue: 0.1333333403, alpha: 1).cgColor
            animationGroup.duration = 1.23
        case .red:
            circleLayer.strokeColor = #colorLiteral(red: 0.9156251231, green: 0.1568627506, blue: 0.07450980693, alpha: 1).cgColor
            animationGroup.duration =  0.92
        case .none:
            circleLayer.strokeColor = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0).cgColor
            animationGroup.duration = 1.88
        }
    }

    func startup() {
        // Create the NISession.
        session = NISession()
        
        // Set the delegate.
        session?.delegate = self
        
        // Since the session is new, this token has not been shared.
        sharedTokenWithPeer = false

        // If `connectedPeer` exists, share the discovery token if needed.
        if connectedPeer != nil && mpc != nil {
            if let myToken = session?.discoveryToken {
                updateInformationLabel(description: "Initializing ...")
                if !sharedTokenWithPeer {
                    shareMyDiscoveryToken(token: myToken)
                }
            } else {
                fatalError("Unable to get self discovery token, is this session invalidated?")
            }
        } else {
            updateInformationLabel(description: "Discovering Peer ...")
            startupMPC()
            
            // Set display state.
            currentDistanceDirectionState = .unknown
            currentSonorState = .none
        }
    }

    // MARK: - NISessionDelegate

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }

        // Find the right peer.
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        guard let nearbyObjectUpdate = peerObj else {
            return
        }

        // Update the the state and visualizations.
        let nextState = getDistanceDirectionState(from: nearbyObjectUpdate)
        updateSonorColorState(from: nearbyObjectUpdate)
        updateVisualization(from: currentDistanceDirectionState, to: nextState, with: nearbyObjectUpdate)
        currentDistanceDirectionState = nextState
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }
        // Find the right peer.
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        if peerObj == nil {
            return
        }

        currentDistanceDirectionState = .unknown
        currentSonorState = .none

        switch reason {
        case .peerEnded:
            // Peer stopped communicating, this session is finished, invalidate.
            session.invalidate()
            
            // Restart the sequence to see if the other side comes back.
            startup()
            
            // Update visuals.
            updateInformationLabel(description: "Peer Ended")
        case .timeout:
            
            // Peer timeout occurred, but the session is still valid.
            // Check the configuration is still valid and re-run the session.
            if let config = session.configuration {
                session.run(config)
            }
            updateInformationLabel(description: "Peer Timeout")
        default:
            fatalError("Unknown and unhandled NINearbyObject.RemovalReason")
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        currentDistanceDirectionState = .unknown
        currentSonorState = .none
        updateInformationLabel(description: "Session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // Session suspension ended. The session can now be run again.
        if let config = self.session?.configuration {
            session.run(config)
        }

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        currentDistanceDirectionState = .unknown
        currentSonorState = .none
        
        // Session was invalidated, startup again to see if everything works.
        startup()
    }

    // MARK: - sharing and receiving discovery token via mpc mechanics

    func startupMPC() {
        if mpc == nil {
            // Avoid any simulator instances from finding any actual devices.
            #if targetEnvironment(simulator)
            mpc = MPCSession(service: "nisample", identity: "com.example.apple-samplecode.simulator.peekaboo-nearbyinteraction", maxPeers: 1)
            #else
            mpc = MPCSession(service: "nisample", identity: "com.example.apple-samplecode.peekaboo-nearbyinteraction", maxPeers: 1)
            #endif
            mpc?.peerConnectedHandler = connectedToPeer
            mpc?.peerDataHandler = dataReceivedHandler
            mpc?.peerDisconnectedHandler = disconnectedFromPeer
        }
        mpc?.invalidate()
        mpc?.start()
    }

    func connectedToPeer(peer: MCPeerID) {
        guard let myToken = session?.discoveryToken else {
            fatalError("Unexpectedly failed to initialize nearby interaction session.")
        }

        if connectedPeer != nil {
            fatalError("Already connected to a peer.")
        }

        if !sharedTokenWithPeer {
            shareMyDiscoveryToken(token: myToken)
        }

        connectedPeer = peer
        peerDisplayName = peer.displayName

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
    }

    func disconnectedFromPeer(peer: MCPeerID) {
        if connectedPeer == peer {
            connectedPeer = nil
            sharedTokenWithPeer = false
        }
    }

    func dataReceivedHandler(data: Data, peer: MCPeerID) {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            fatalError("Unexpectedly failed to decode discovery token.")
        }
        peerDidShareDiscoveryToken(peer: peer, token: discoveryToken)
    }

    func shareMyDiscoveryToken(token: NIDiscoveryToken) {
        guard let encodedData = try?  NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            fatalError("Unexpectedly failed to encode discovery token.")
        }
        mpc?.sendDataToAllPeers(data: encodedData)
        sharedTokenWithPeer = true
    }

    func peerDidShareDiscoveryToken(peer: MCPeerID, token: NIDiscoveryToken) {
        if connectedPeer != peer {
            fatalError("Received token from unexpected peer.")
        }
        // Create an NI configuration
        peerDiscoveryToken = token

        let config = NINearbyPeerConfiguration(peerToken: token)

        // Run the session
        session?.run(config)
    }

    // MARK: - Visualizations
    func isNearby(_ distance: Float) -> Bool {
        return distance < nearbyDistanceThreshold
    }

    func isPointingAt(_ angleRad: Float) -> Bool {
        return abs(angleRad.radiansToDegrees) <= 15 // let's say that -15 to +15 degrees means pointing at
    }

    func getDistanceDirectionState(from nearbyObject: NINearbyObject) -> DistanceDirectionState {
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            return .unknown
        }

        let isNearby = nearbyObject.distance.map(isNearby(_:)) ?? false
        let directionAvailable = nearbyObject.direction != nil

        if isNearby && directionAvailable {
            return .closeUpInFOV
        }

        if !isNearby && directionAvailable {
            return .notCloseUpInFOV
        }

        return .outOfFOV
    }
    
    func updateSonorColorState(from nearbyObject: NINearbyObject) {
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            currentSonorState = .none
            return
        }

        let isNearby = nearbyObject.distance.map(isNearby(_:)) ?? false
        let directionAvailable = nearbyObject.direction != nil

        if isNearby && directionAvailable {
            currentSonorState = .red
            return
        }

        if !isNearby && directionAvailable {
            currentSonorState = .yellow
            return
        }

        currentSonorState = .green
    }

    private func animate(from currentState: DistanceDirectionState, to nextState: DistanceDirectionState, with peer: NINearbyObject) {
        let azimuth = peer.direction.map(azimuth(from:))
        let elevation = peer.direction.map(elevation(from:))

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
        
        // If transitioning from unavailable state, bring the monkey and details into view,
        //  hide the center inforamtion label.
        if currentState == .unknown && nextState != .unknown {
            monkeyLabel.alpha = 1.0
            centerInformationLabel.alpha = 0.0
            detailContainer.alpha = 1.0
        }
        
        if nextState == .unknown {
            monkeyLabel.alpha = 0.0
            centerInformationLabel.alpha = 1.0
            detailContainer.alpha = 0.0
        }
        
        if nextState == .outOfFOV || nextState == .unknown {
            detailAngleInfoView.alpha = 0.0
        } else {
            detailAngleInfoView.alpha = 1.0
        }
        
        // Update the monkey label based on the next state.
        switch nextState {
        case .closeUpInFOV:
            monkeyLabel.text = "🙉"
        case .notCloseUpInFOV:
            monkeyLabel.text = "🙈"
        case .outOfFOV:
            monkeyLabel.text = "🙊"
        case .unknown:
            monkeyLabel.text = ""
        }
        
        if peer.distance != nil {
            detailDistanceLabel.text = String(format: "%0.2f m", peer.distance!)
        }
        
        monkeyLabel.transform = CGAffineTransform(rotationAngle: CGFloat(azimuth ?? 0.0))
        
        // No more visuals need to be updated if out of field of view or unavailable.
        if nextState == .outOfFOV || nextState == .unknown {
            return
        }
        
        if elevation != nil {
            if elevation! < 0 {
                detailDownArrow.alpha = 1.0
                detailUpArrow.alpha = 0.0
            } else {
                detailDownArrow.alpha = 0.0
                detailUpArrow.alpha = 1.0
            }
            
            if isPointingAt(elevation!) {
                detailElevationLabel.alpha = 1.0
            } else {
                detailElevationLabel.alpha = 0.5
            }
            detailElevationLabel.text = String(format: "% 3.0f°", elevation!.radiansToDegrees)
        }
        
        if azimuth != nil {
            if isPointingAt(azimuth!) {
                detailAzimuthLabel.alpha = 1.0
                detailLeftArrow.alpha = 0.25
                detailRightArrow.alpha = 0.25
            } else {
                detailAzimuthLabel.alpha = 0.5
                if azimuth! < 0 {
                    detailLeftArrow.alpha = 1.0
                    detailRightArrow.alpha = 0.25
                } else {
                    detailLeftArrow.alpha = 0.25
                    detailRightArrow.alpha = 1.0
                }
            }
            detailAzimuthLabel.text = String(format: "% 3.0f°", azimuth!.radiansToDegrees)
        }
    }
    
    func updateVisualization(from currentState: DistanceDirectionState, to nextState: DistanceDirectionState, with peer: NINearbyObject) {
        // Peekaboo or first measurement - use haptics.
        if currentState == .notCloseUpInFOV && nextState == .closeUpInFOV || currentState == .unknown {
            impactGenerator.impactOccurred()
        }

        // Animate into the next visuals.
        UIView.animate(withDuration: 0.3, animations: {
            self.animate(from: currentState, to: nextState, with: peer)
        })
    }

    func updateInformationLabel(description: String) {
        UIView.animate(withDuration: 0.3, animations: {
            self.monkeyLabel.alpha = 0.0
            self.detailContainer.alpha = 0.0
            self.centerInformationLabel.alpha = 1.0
            self.centerInformationLabel.text = description
        })
    }
}
